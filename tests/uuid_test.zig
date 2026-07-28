const std = @import("std");
const testing = std.testing;
const zuuid = @import("zuuid");
const Uuid = zuuid.Uuid;

fn timestampOf(u: Uuid) u48 {
    return std.mem.readInt(u48, u.bytes[0..6], .big);
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
    const u = Uuid.v7At(random, unix_ms);

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
        const u = Uuid.v7At(random, ts);
        try testing.expectEqual(@as(u4, 7), u.version());
        try testing.expectEqual(@as(u8, 0b10), u.bytes[8] >> 6);
        const field = timestampOf(u);
        try testing.expect(field >= prev);
        prev = field;
    }
}

test "round-trip: parse(toString(u)) == u, for v4 and v7" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();

    for (0..50) |_| {
        const v4 = Uuid.v4(random);
        var buf4: [36]u8 = undefined;
        const parsed4 = try Uuid.parse(v4.toString(&buf4));
        try testing.expect(v4.eql(parsed4));

        const v7 = Uuid.v7At(random, 123_456_789);
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
