const std = @import("std");
const testing = std.testing;
const zuuid = @import("zuuid");
const Uuid = zuuid.Uuid;

fn timestampOf(u: Uuid) u48 {
    return std.mem.readInt(u48, u.bytes[0..6], .big);
}

fn randAOf(u: Uuid) u12 {
    return (@as(u12, u.bytes[6] & 0x0F) << 8) | u.bytes[7];
}

test "v4: version nibble, variant bits, no collisions in a sample" {
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const random = prng.random();

    var seen: [200]Uuid = undefined;
    for (0..seen.len) |i| {
        const u = Uuid.v4(random);
        try testing.expectEqual(@as(u4, 4), u.version());
        try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
        seen[i] = u;
    }

    for (0..seen.len) |i| {
        for (i + 1..seen.len) |j| {
            try testing.expect(!seen[i].eql(seen[j]));
        }
    }
}

test "v7: fixed timestamp lands in the top 48 bits exactly" {
    var prng = std.Random.DefaultPrng.init(1);
    const random = prng.random();

    const unix_ms: i64 = 0x010203040506;
    const u = try Uuid.v7At(random, unix_ms);

    try testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 }, u.bytes[0..6]);
    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
}

test "v7: timestamp field is nondecreasing as unix_ms increases" {
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    const timestamps = [_]i64{ 1_000, 1_001, 2_000, 1_000_000, 1_000_000_000_000 };
    var prev: u48 = 0;
    for (timestamps) |ts| {
        const u = try Uuid.v7At(random, ts);
        try testing.expectEqual(@as(u4, 7), u.version());
        try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
        const field = timestampOf(u);
        try testing.expect(field >= prev);
        prev = field;
    }
}

test "v7: wall clock stamps version 7 and RFC variant" {
    var prng = std.Random.DefaultPrng.init(1);
    const u = try Uuid.v7(prng.random(), testing.io);
    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
}

test "v7At rejects unix_ms outside the RFC 48-bit range" {
    var prng = std.Random.DefaultPrng.init(1);
    const random = prng.random();

    try testing.expectError(error.InvalidTimestamp, Uuid.v7At(random, -1));
    try testing.expectError(error.InvalidTimestamp, Uuid.v7At(random, 1 << 48));

    const epoch = try Uuid.v7At(random, 0);
    try testing.expectEqual(@as(u48, 0), timestampOf(epoch));

    const max_ms: i64 = std.math.maxInt(u48);
    const max_u = try Uuid.v7At(random, max_ms);
    try testing.expectEqual(@as(u48, std.math.maxInt(u48)), timestampOf(max_u));
}

test "round-trip: parse(toString(u)) == u, for v4 and v7" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();

    for (0..50) |_| {
        const v4 = Uuid.v4(random);
        var buf4: [36]u8 = undefined;
        const parsed4 = try Uuid.parse(v4.toString(&buf4));
        try testing.expect(v4.eql(parsed4));

        const v7 = try Uuid.v7At(random, 123_456_789);
        var buf7: [36]u8 = undefined;
        const parsed7 = try Uuid.parse(v7.toString(&buf7));
        try testing.expect(v7.eql(parsed7));
    }
}

test "toString produces the canonical dashed lowercase form" {
    var prng = std.Random.DefaultPrng.init(99);
    const random = prng.random();
    const u = Uuid.v4(random);

    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);

    try testing.expectEqual(@as(usize, 36), s.len);
    try testing.expectEqual(@as(u8, '-'), s[8]);
    try testing.expectEqual(@as(u8, '-'), s[13]);
    try testing.expectEqual(@as(u8, '-'), s[18]);
    try testing.expectEqual(@as(u8, '-'), s[23]);
    for (s, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) continue;
        try testing.expect(std.ascii.isDigit(c) or (c >= 'a' and c <= 'f'));
    }
}

test "format writes the canonical dashed form via {f}" {
    const u = try Uuid.parse("3f2504e0-4f89-41d3-9a0c-0305e82c3301");
    var buf: [36]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try w.print("{f}", .{u});
    try testing.expectEqualStrings("3f2504e0-4f89-41d3-9a0c-0305e82c3301", w.buffered());
}

test "parse accepts uppercase and mixed-case hex" {
    const lower = try Uuid.parse("3f2504e0-4f89-41d3-9a0c-0305e82c3301");
    const upper = try Uuid.parse("3F2504E0-4F89-41D3-9A0C-0305E82C3301");
    const mixed = try Uuid.parse("3f2504E0-4F89-41d3-9A0C-0305e82c3301");
    try testing.expect(lower.eql(upper));
    try testing.expect(lower.eql(mixed));
    try testing.expectEqual(@as(u4, 4), upper.version());
}

test "parse copies hex as-is without stamping version or variant" {
    const nil_uuid = try Uuid.parse("00000000-0000-0000-0000-000000000000");
    try testing.expectEqual(@as(u4, 0), nil_uuid.version());
    try testing.expectEqual(@as(u8, 0), nil_uuid.bytes[8] >> 6);
}

test "RFC 9562 Appendix A.4 UUIDv7 vector" {
    // unix_ts_ms = 0x017F22E279B0, ver = 7, rand_a = 0xCC3,
    // var = 10, rand_b = 0x18C4DC0C0C07398F
    const text = "017F22E2-79B0-7CC3-98C4-DC0C0C07398F";
    const u = try Uuid.parse(text);

    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
    try testing.expectEqual(@as(u48, 0x017F22E279B0), timestampOf(u));

    var buf: [36]u8 = undefined;
    try testing.expectEqualStrings("017f22e2-79b0-7cc3-98c4-dc0c0c07398f", u.toString(&buf));

    var prng = std.Random.DefaultPrng.init(1);
    const generated = try Uuid.v7At(prng.random(), 0x017F22E279B0);
    try testing.expectEqual(@as(u48, 0x017F22E279B0), timestampOf(generated));
    try testing.expectEqual(@as(u4, 7), generated.version());
}

test "order is lexicographic on RFC bytes" {
    const a = try Uuid.parse("017f22e2-79b0-7cc3-98c4-dc0c0c07398f");
    const b = try Uuid.parse("017f22e2-79b0-7cc3-98c4-dc0c0c073990");
    try testing.expectEqual(std.math.Order.eq, a.order(a));
    try testing.expectEqual(std.math.Order.lt, a.order(b));
    try testing.expectEqual(std.math.Order.gt, b.order(a));
}

test "V7Generator is strictly increasing within the same millisecond" {
    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();
    var gen: Uuid.V7Generator = .{};

    var prev = try gen.nextAt(random, 1_000);
    try testing.expectEqual(@as(u4, 7), prev.version());
    try testing.expectEqual(@as(u8, 0b10), prev.bytes[8] >> 6);

    for (0..200) |_| {
        const u = try gen.nextAt(random, 1_000);
        try testing.expectEqual(std.math.Order.lt, prev.order(u));
        try testing.expectEqual(@as(u4, 7), u.version());
        try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
        if (timestampOf(prev) == timestampOf(u)) {
            try testing.expectEqual(@as(u12, randAOf(prev) + 1), randAOf(u));
        } else {
            try testing.expectEqual(@as(u48, timestampOf(prev) + 1), timestampOf(u));
        }
        prev = u;
    }
}

test "V7Generator freezes timestamp when the clock goes backward" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    var gen: Uuid.V7Generator = .{
        .last_ms = 5_000,
        .seq = 10,
    };

    const after_regression = try gen.nextAt(random, 4_000);
    try testing.expectEqual(@as(u48, 5_000), timestampOf(after_regression));
    try testing.expectEqual(@as(u12, 11), randAOf(after_regression));
    try testing.expectEqual(@as(u4, 7), after_regression.version());
}

test "V7Generator bumps the millisecond when rand_a is exhausted" {
    var prng = std.Random.DefaultPrng.init(99);
    const random = prng.random();
    var gen: Uuid.V7Generator = .{
        .last_ms = 100,
        .seq = std.math.maxInt(u12),
    };

    const u = try gen.nextAt(random, 100);
    try testing.expectEqual(@as(u48, 101), timestampOf(u));
    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(?u48, 101), gen.last_ms);
    try testing.expectEqual(gen.seq, randAOf(u));
}

test "V7Generator fails when a seq overflow would exceed the 48-bit timestamp" {
    var prng = std.Random.DefaultPrng.init(1);
    var gen: Uuid.V7Generator = .{
        .last_ms = std.math.maxInt(u48),
        .seq = std.math.maxInt(u12),
    };
    try testing.expectError(error.InvalidTimestamp, gen.nextAt(prng.random(), std.math.maxInt(u48)));
}

test "V7Generator.next stamps version 7 from the wall clock" {
    var prng = std.Random.DefaultPrng.init(1);
    var gen: Uuid.V7Generator = .{};
    const u = try gen.next(prng.random(), testing.io);
    try testing.expectEqual(@as(u4, 7), u.version());
    try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
}

test "parse rejects malformed input" {
    try testing.expectError(error.InvalidFormat, Uuid.parse("too-short"));
    try testing.expectError(error.InvalidFormat, Uuid.parse("0102030405060708090a0b0c0d0e0f011")); // no dashes, wrong length
    try testing.expectError(error.InvalidFormat, Uuid.parse("01020304-0506-0708-090a-0b0c0d0e0fzz")); // non-hex chars

    // Wrong dash positions: valid length, dashes shifted by one.
    try testing.expectError(error.InvalidFormat, Uuid.parse("010203040-506-0708-090a-0b0c0d0e0f00"));

    // An extra dash swapped in for a hex digit -- length stays 36, but a
    // required dash slot no longer holds '-', so this must be rejected
    // rather than misparsed or crash on an out-of-bounds read.
    try testing.expectError(error.InvalidFormat, Uuid.parse("01020304-0506-0708-090a-0b0c0d0e0f-0"));
}
