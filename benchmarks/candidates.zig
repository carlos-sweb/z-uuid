//! Benchmark-only alternatives. The frozen implementation remains unchanged.
const std = @import("std");
pub const Old = @import("baseline/uuid.zig").Uuid;
pub const positions = [16]usize{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
const hex = "0123456789abcdef";
const pairs: [256][2]u8 = blk: {
    var result: [256][2]u8 = undefined;
    for (&result, 0..) |*entry, i| entry.* = .{ hex[i >> 4], hex[i & 15] };
    break :blk result;
};
const decode: [256]u8 = blk: {
    var result: [256]u8 = @splat(255);
    for (0..10) |i| result['0' + i] = @intCast(i);
    for (0..6) |i| {
        result['a' + i] = @intCast(i + 10);
        result['A' + i] = @intCast(i + 10);
    }
    break :blk result;
};

pub fn order128(a: Old, b: Old) std.math.Order {
    return std.math.order(std.mem.readInt(u128, &a.bytes, .big), std.mem.readInt(u128, &b.bytes, .big));
}
pub fn order64(a: Old, b: Old) std.math.Order {
    const high = std.math.order(std.mem.readInt(u64, a.bytes[0..8], .big), std.mem.readInt(u64, b.bytes[0..8], .big));
    return if (high != .eq) high else std.math.order(std.mem.readInt(u64, a.bytes[8..16], .big), std.mem.readInt(u64, b.bytes[8..16], .big));
}
pub fn toString(a: Old, buf: *[36]u8) []const u8 {
    inline for (positions, 0..) |p, i| buf[p..][0..2].* = pairs[a.bytes[i]];
    inline for (.{ 8, 13, 18, 23 }) |p| buf[p] = '-';
    return buf;
}
fn hexValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}
pub fn parse(comptime table: bool, text: []const u8) Old.ParseError!Old {
    if (text.len != 36) return error.InvalidFormat;
    if (text[8] != '-' or text[13] != '-' or text[18] != '-' or text[23] != '-') return error.InvalidFormat;
    var bytes: [16]u8 = undefined;
    inline for (positions, 0..) |p, i| {
        if (table) {
            const hi = decode[text[p]];
            const lo = decode[text[p + 1]];
            if ((hi | lo) == 255) return error.InvalidFormat;
            bytes[i] = (hi << 4) | lo;
        } else {
            const hi = hexValue(text[p]) orelse return error.InvalidFormat;
            const lo = hexValue(text[p + 1]) orelse return error.InvalidFormat;
            bytes[i] = (hi << 4) | lo;
        }
    }
    return .{ .bytes = bytes };
}
fn parts(ts: u48, seq: u12, tail: [8]u8) Old {
    var result: Old = undefined;
    std.mem.writeInt(u48, result.bytes[0..6], ts, .big);
    result.bytes[6] = 0x70 | @as(u8, @truncate(seq >> 8));
    result.bytes[7] = @truncate(seq);
    result.bytes[8..16].* = tail;
    result.bytes[8] = 0x80 | (result.bytes[8] & 63);
    return result;
}
pub fn v7At(random: std.Random, unix_ms: i64) Old.TimestampError!Old {
    const ts = std.math.cast(u48, unix_ms) orelse return error.InvalidTimestamp;
    var entropy: [10]u8 = undefined;
    random.bytes(&entropy);
    return parts(ts, @truncate(std.mem.readInt(u16, entropy[0..2], .little)), entropy[2..10].*);
}
pub fn v7(random: std.Random, io: std.Io) Old.TimestampError!Old {
    const ns = std.Io.Clock.real.now(io).nanoseconds;
    const ms = std.math.cast(i64, @divFloor(ns, std.time.ns_per_ms)) orelse return error.InvalidTimestamp;
    return v7At(random, ms);
}
pub fn Generator(comptime policy: bool) type {
    return struct {
        last_ms: ?u48 = null,
        seq: u12 = 0,
        pub fn next(self: *@This(), random: std.Random, io: std.Io) Old.TimestampError!Old {
            const ns = std.Io.Clock.real.now(io).nanoseconds;
            const ms = std.math.cast(i64, @divFloor(ns, std.time.ns_per_ms)) orelse return error.InvalidTimestamp;
            return self.nextAt(random, ms);
        }
        pub fn nextAt(self: *@This(), random: std.Random, unix_ms: i64) Old.TimestampError!Old {
            const ts = std.math.cast(u48, unix_ms) orelse return error.InvalidTimestamp;
            var issued_ms = ts;
            var reseed = true;
            if (self.last_ms) |last| {
                if (ts <= last) {
                    issued_ms = last;
                    if (self.seq == std.math.maxInt(u12)) {
                        if (last == std.math.maxInt(u48)) return error.InvalidTimestamp;
                        issued_ms += 1;
                    } else {
                        reseed = false;
                    }
                }
            }
            var tail: [8]u8 = undefined;
            if (reseed) {
                var entropy: [10]u8 = undefined;
                random.bytes(&entropy);
                self.seq = @truncate(std.mem.readInt(u16, entropy[0..2], .little));
                if (policy) self.seq &= 0x7ff;
                tail = entropy[2..10].*;
            } else {
                self.seq += 1;
                random.bytes(&tail);
            }
            self.last_ms = issued_ms;
            return parts(issued_ms, self.seq, tail);
        }
    };
}
