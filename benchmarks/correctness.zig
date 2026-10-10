const std = @import("std");
const t = std.testing;
const Old = @import("baseline/uuid.zig").Uuid;
const New = @import("zuuid").Uuid;
const candidates = @import("candidates.zig");

fn checkParse(text: []const u8) !void {
    const reference = Old.parse(text);
    if (reference) |expected| {
        const actual = try New.parse(text);
        try t.expectEqualSlices(u8, &expected.bytes, &actual.bytes);
        inline for (.{ false, true }) |table| {
            const candidate = try candidates.parse(table, text);
            try t.expectEqualSlices(u8, &expected.bytes, &candidate.bytes);
        }
    } else |err| {
        try t.expectError(err, New.parse(text));
        try t.expectError(err, candidates.parse(false, text));
        try t.expectError(err, candidates.parse(true, text));
    }
}

test "parse agrees with baseline for all byte substitutions at all positions" {
    const canonical = "01234567-89ab-cdef-0123-456789abcdef";
    try checkParse(canonical);
    for (0..canonical.len) |p| {
        for (0..256) |byte| {
            var text = canonical.*;
            text[p] = @intCast(byte);
            try checkParse(&text);
        }
    }
    for (0..80) |len| {
        var text: [80]u8 = @splat('0');
        try checkParse(text[0..len]);
    }
}

test "arbitrary binary values round trip and match formatting and comparisons" {
    var prng = std.Random.DefaultPrng.init(0x17);
    for (0..4096) |_| {
        const a: Old = .{ .bytes = prng.random().array(u8, 16) };
        const b: Old = .{ .bytes = prng.random().array(u8, 16) };
        const na: New = .{ .bytes = a.bytes };
        const nb: New = .{ .bytes = b.bytes };
        var old_buf: [36]u8 = undefined;
        var new_buf: [36]u8 = undefined;
        var candidate_buf: [36]u8 = undefined;
        try t.expectEqualStrings(a.toString(&old_buf), na.toString(&new_buf));
        try t.expectEqualStrings(&old_buf, candidates.toString(a, &candidate_buf));
        const round_trip = try New.parse(&new_buf);
        try t.expectEqualSlices(u8, &na.bytes, &round_trip.bytes);
        try t.expectEqual(a.order(b), na.order(nb));
        try t.expectEqual(a.order(b), candidates.order128(a, b));
        try t.expectEqual(a.order(b), candidates.order64(a, b));
        try t.expectEqual(a.eql(b), na.eql(nb));
        try t.expect(na.eql(na));
    }
}

test "ordering preserves each byte significance and equality" {
    const zero: Old = .{ .bytes = @splat(0) };
    for (0..16) |p| {
        var greater = zero;
        greater.bytes[p] = 1;
        const a: New = .{ .bytes = zero.bytes };
        const b: New = .{ .bytes = greater.bytes };
        try t.expectEqual(std.math.Order.lt, a.order(b));
        try t.expectEqual(std.math.Order.gt, b.order(a));
        try t.expectEqual(std.math.Order.eq, b.order(b));
        try t.expectEqual(zero.order(greater), candidates.order128(zero, greater));
        try t.expectEqual(zero.order(greater), candidates.order64(zero, greater));
        if (p + 1 < 16) {
            var later = zero;
            later.bytes[p + 1] = 255;
            try t.expectEqual(std.math.Order.gt, b.order(.{ .bytes = later.bytes }));
        }
    }
}

const Entropy = struct {
    byte: u8,
    calls: usize = 0,
    bytes: usize = 0,
    fn fill(ptr: *Entropy, buf: []u8) void {
        ptr.calls += 1;
        ptr.bytes += buf.len;
        @memset(buf, ptr.byte);
    }
    fn random(self: *Entropy) std.Random {
        return .init(self, fill);
    }
};

test "controlled entropy verifies v4 and v7 layouts exactly" {
    inline for (.{ @as(u8, 0), @as(u8, 255) }) |byte| {
        var entropy: Entropy = .{ .byte = byte };
        var expected: [16]u8 = @splat(byte);
        expected[6] = (byte & 15) | 0x40;
        expected[8] = (byte & 63) | 0x80;
        const v4 = New.v4(entropy.random());
        try t.expectEqualSlices(u8, &expected, &v4.bytes);
        try t.expectEqual(@as(usize, 1), entropy.calls);
        const v7 = try New.v7At(entropy.random(), 0x010203040506);
        expected[0..6].* = .{ 1, 2, 3, 4, 5, 6 };
        expected[6] = (byte & 15) | 0x70;
        try t.expectEqualSlices(u8, &expected, &v7.bytes);
        const grouped = try candidates.v7At(entropy.random(), 0x010203040506);
        try t.expectEqualSlices(u8, &expected, &grouped.bytes);
    }
}

test "11-bit seed extremes guarantee 2049 emissions before timestamp advance" {
    inline for (.{ @as(u8, 0), @as(u8, 255) }) |byte| {
        var entropy: Entropy = .{ .byte = byte };
        var generator: New.V7Generator = .{};
        var prev = try generator.nextAt(entropy.random(), 100);
        const seed: u12 = if (byte == 0) 0 else 2047;
        try t.expectEqual(seed, generator.seq);
        const capacity: usize = 4096 - @as(usize, seed);
        try t.expect(capacity >= 2049);
        for (1..capacity) |_| {
            const next = try generator.nextAt(entropy.random(), 100);
            try t.expectEqual(@as(?u48, 100), generator.last_ms);
            try t.expectEqual(std.math.Order.lt, prev.order(next));
            prev = next;
        }
        const overflow = try generator.nextAt(entropy.random(), 100);
        try t.expectEqual(@as(?u48, 101), generator.last_ms);
        try t.expectEqual(seed, generator.seq);
        try t.expectEqual(std.math.Order.lt, prev.order(overflow));
    }
}

test "long stream stays monotonic across overflow regression and clock recovery" {
    var prng = std.Random.DefaultPrng.init(123);
    var generator: New.V7Generator = .{};
    var prev = try generator.nextAt(prng.random(), 1000);
    for (0..30_000) |i| {
        const ms: i64 = if (i < 20_000) 1000 else if (i < 25_000) 500 else 100_000 + @as(i64, @intCast(i));
        const next = try generator.nextAt(prng.random(), ms);
        try t.expectEqual(std.math.Order.lt, prev.order(next));
        try t.expectEqual(@as(u4, 7), next.version());
        try t.expectEqual(@as(u8, 2), next.bytes[8] >> 6);
        prev = next;
    }
}

test "generator errors preserve state and do not request entropy" {
    var entropy: Entropy = .{ .byte = 255 };
    var generator: New.V7Generator = .{ .last_ms = std.math.maxInt(u48), .seq = std.math.maxInt(u12) };
    const before = generator;
    for ([_]i64{ -1, 1 << 48, std.math.maxInt(u48) }) |ms| {
        try t.expectError(error.InvalidTimestamp, generator.nextAt(entropy.random(), ms));
        try t.expectEqual(before.last_ms, generator.last_ms);
        try t.expectEqual(before.seq, generator.seq);
        try t.expectEqual(@as(usize, 0), entropy.calls);
    }
    generator = .{};
    try t.expectError(error.InvalidTimestamp, generator.nextAt(entropy.random(), -1));
    try t.expectEqual(@as(?u48, null), generator.last_ms);
    const epoch = try generator.nextAt(entropy.random(), 0);
    try t.expectEqual(@as(u48, 0), std.mem.readInt(u48, epoch.bytes[0..6], .big));
}

test "format propagates writer failures" {
    const value: New = .{ .bytes = @splat(0) };
    var writer: std.Io.Writer = .failing;
    try t.expectError(error.WriteFailed, value.format(&writer));
}

// Keep speculative variants covered even when benchmarks reject them.
test "grouped generator candidates remain monotonic with both seed policies" {
    inline for (.{ false, true }) |policy| {
        var entropy: Entropy = .{ .byte = 255 };
        var generator: candidates.Generator(policy) = .{};
        var prev = try generator.nextAt(entropy.random(), 1000);
        for (0..10_000) |_| {
            const next = try generator.nextAt(entropy.random(), 500);
            try t.expectEqual(std.math.Order.lt, prev.order(next));
            prev = next;
        }
        generator = .{ .last_ms = std.math.maxInt(u48), .seq = std.math.maxInt(u12) };
        try t.expectError(error.InvalidTimestamp, generator.nextAt(entropy.random(), std.math.maxInt(u48)));
        try t.expectEqual(@as(u12, 4095), generator.seq);
    }
}

const FixedClock = struct {
    ns: i96,
    fn now(userdata: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
        const self: *FixedClock = @ptrCast(@alignCast(userdata.?));
        return .{ .nanoseconds = self.ns };
    }
};

test "wall clock conversion validates negative sub-ms and i96 extremes" {
    var clock: FixedClock = .{ .ns = 0 };
    var vtable = t.io.vtable.*;
    vtable.now = FixedClock.now;
    const io: std.Io = .{ .userdata = &clock, .vtable = &vtable };
    var entropy: Entropy = .{ .byte = 0 };
    var generator: New.V7Generator = .{};
    for ([_]i96{ -1, std.math.minInt(i96), std.math.maxInt(i96), (@as(i96, 1) << 48) * std.time.ns_per_ms }) |ns| {
        clock.ns = ns;
        try t.expectError(error.InvalidTimestamp, New.v7(entropy.random(), io));
        try t.expectError(error.InvalidTimestamp, generator.next(entropy.random(), io));
        try t.expectEqual(@as(usize, 0), entropy.calls);
        try t.expectEqual(@as(?u48, null), generator.last_ms);
    }
    clock.ns = 999_999;
    const epoch = try New.v7(entropy.random(), io);
    try t.expectEqual(@as(u48, 0), std.mem.readInt(u48, epoch.bytes[0..6], .big));
    clock.ns = @as(i96, std.math.maxInt(u48)) * std.time.ns_per_ms + 999_999;
    const upper = try generator.next(entropy.random(), io);
    try t.expectEqual(@as(u48, std.math.maxInt(u48)), std.mem.readInt(u48, upper.bytes[0..6], .big));
}
