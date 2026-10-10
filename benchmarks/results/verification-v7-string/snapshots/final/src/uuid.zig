//! UUID v4 (random) and v7 (time-ordered), per RFC 9562.
const std = @import("std");

const hex_positions = [16]usize{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
const hex_pairs: [256][2]u8 = blk: {
    const chars = "0123456789abcdef";
    var result: [256][2]u8 = undefined;
    for (&result, 0..) |*entry, i| entry.* = .{ chars[i >> 4], chars[i & 15] };
    break :blk result;
};

/// A 128-bit UUID in the RFC 9562 big-endian byte layout.
/// `v4`, `v7`, and `v7At` stamp the version nibble and RFC variant `10`.
/// `parse` copies the canonical hex form as-is and does not rewrite those
/// fields, so a parsed value can carry any version or variant.
pub const Uuid = struct {
    bytes: [16]u8,

    /// Random UUID (RFC 9562 §5.4): 122 bits from the supplied source, version
    /// nibble `0100` and variant bits `10` stamped over the rest.
    /// The caller must supply a CSPRNG when unpredictability is required.
    pub fn v4(random: std.Random) Uuid {
        var bytes: [16]u8 = undefined;
        random.bytes(&bytes);
        bytes[6] = 0x40 | (bytes[6] & 0x0F);
        bytes[8] = 0x80 | (bytes[8] & 0x3F);
        return .{ .bytes = bytes };
    }

    pub const TimestampError = error{InvalidTimestamp};

    /// Time-ordered UUID (RFC 9562 §5.7) using the current wall clock.
    /// The caller supplies `io` for the clock and `random` for entropy.
    ///
    /// Returns `error.InvalidTimestamp` if the wall clock is outside the
    /// RFC 48-bit Unix-millisecond range `[0, 2^48-1]`.
    pub fn v7(random: std.Random, io: std.Io) TimestampError!Uuid {
        return v7At(random, try currentUnixMs(io));
    }

    /// Same as `v7`, but with an explicit millisecond timestamp instead
    /// of reading the wall clock -- lets callers (and tests) produce
    /// deterministic, reproducible UUIDs. `unix_ms` must be in
    /// `[0, 2^48-1]`; anything else is `error.InvalidTimestamp`.
    ///
    /// Stateless: `rand_a` is fresh entropy, so two values from the same
    /// millisecond can sort in either order. For monotonic IDs (database
    /// keys), use `V7Generator`.
    pub fn v7At(random: std.Random, unix_ms: i64) TimestampError!Uuid {
        const ts = std.math.cast(u48, unix_ms) orelse return error.InvalidTimestamp;
        return fromV7Parts(ts, random.int(u12), random);
    }

    /// Monotonic UUIDv7 generator (RFC 9562 §6.2 Method 1).
    ///
    /// Owns a 12-bit `rand_a` counter and the last issued millisecond.
    /// Keep one instance per stream of IDs (typically per thread); this
    /// type does not synchronize. No heap, no globals.
    ///
    /// - New wall-clock millisecond: seed the low 11 bits of `seq` from
    ///   `random`, leaving the high bit zero for rollover headroom.
    /// - Same millisecond, or a clock regression: freeze the issued
    ///   timestamp and increment `seq`.
    /// - `seq` exhausted (after at most `2^12` IDs, depending on the seed):
    ///   bump the issued millisecond by 1
    ///   and reseed, so ordering never wraps. A newly seeded timestamp
    ///   accommodates at least 2049 IDs before exhaustion. Fails with
    ///   `error.InvalidTimestamp` if that bump would exceed `2^48-1`.
    /// The issued timestamp can therefore run ahead of the wall clock.
    /// Strict ordering applies only to sequential calls on this instance;
    /// an error leaves its state unchanged.
    pub const V7Generator = struct {
        last_ms: ?u48 = null,
        seq: u12 = 0,

        /// Like `Uuid.v7`, but monotonic across calls on this generator.
        pub fn next(self: *V7Generator, random: std.Random, io: std.Io) TimestampError!Uuid {
            return self.nextAt(random, try currentUnixMs(io));
        }

        /// Like `Uuid.v7At`, but monotonic across calls on this generator.
        pub fn nextAt(self: *V7Generator, random: std.Random, unix_ms: i64) TimestampError!Uuid {
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
                // One request supplies the seed and rand_b together. The high
                // counter bit remains zero, leaving at least 2049 emissions.
                var entropy: [10]u8 = undefined;
                random.bytes(&entropy);
                self.seq = @as(u12, @truncate(std.mem.readInt(u16, entropy[0..2], .little))) & 0x7ff;
                tail = entropy[2..10].*;
            } else {
                self.seq += 1;
                random.bytes(&tail);
            }
            self.last_ms = issued_ms;
            return fromV7Entropy(issued_ms, self.seq, tail);
        }
    };

    fn currentUnixMs(io: std.Io) TimestampError!i64 {
        const ts = std.Io.Clock.real.now(io);
        return std.math.cast(i64, @divFloor(ts.nanoseconds, std.time.ns_per_ms)) orelse
            error.InvalidTimestamp;
    }

    fn fromV7Parts(ts: u48, rand_a: u12, random: std.Random) Uuid {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u48, bytes[0..6], ts, .big);
        bytes[6] = 0x70 | @as(u8, @truncate(rand_a >> 8));
        bytes[7] = @truncate(rand_a);
        random.bytes(bytes[8..16]);
        bytes[8] = 0x80 | (bytes[8] & 0x3F);
        return .{ .bytes = bytes };
    }

    // Keep stateless RNG requests separate: grouping them regressed seeded
    // PRNG performance. The generator already has a seed/tail entropy block.
    fn fromV7Entropy(ts: u48, rand_a: u12, tail: [8]u8) Uuid {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u48, bytes[0..6], ts, .big);
        bytes[6] = 0x70 | @as(u8, @truncate(rand_a >> 8));
        bytes[7] = @truncate(rand_a);
        bytes[8..16].* = tail;
        bytes[8] = 0x80 | (bytes[8] & 0x3F);
        return .{ .bytes = bytes };
    }

    /// The version nibble (4 for `v4`, 7 for `v7`).
    pub fn version(self: Uuid) u4 {
        return @truncate(self.bytes[6] >> 4);
    }

    pub fn eql(a: Uuid, b: Uuid) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }

    /// Lexicographic order on the RFC byte layout. For v7 values this
    /// is chronological (timestamp, then `rand_a`, then `rand_b`).
    pub fn order(a: Uuid, b: Uuid) std.math.Order {
        const high = std.math.order(
            std.mem.readInt(u64, a.bytes[0..8], .big),
            std.mem.readInt(u64, b.bytes[0..8], .big),
        );
        return if (high != .eq) high else std.math.order(
            std.mem.readInt(u64, a.bytes[8..16], .big),
            std.mem.readInt(u64, b.bytes[8..16], .big),
        );
    }

    /// Formats into the canonical lowercase `8-4-4-4-12` dashed form
    /// without allocating. The returned slice borrows `buf` and remains
    /// valid only while that buffer is alive and unchanged.
    pub fn toString(self: Uuid, buf: *[36]u8) []const u8 {
        inline for (hex_positions, 0..) |p, i| buf[p..][0..2].* = hex_pairs[self.bytes[i]];
        inline for (.{ 8, 13, 18, 23 }) |p| buf[p] = '-';
        return buf;
    }

    pub fn format(self: Uuid, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [36]u8 = undefined;
        try w.writeAll(self.toString(&buf));
    }

    pub const ParseError = error{InvalidFormat};

    /// Parses the canonical lowercase-or-uppercase `8-4-4-4-12` dashed
    /// form. Any other shape (no dashes, braces, wrong length) is
    /// `error.InvalidFormat` -- narrow on purpose.
    pub fn parse(text: []const u8) ParseError!Uuid {
        if (text.len != 36) return error.InvalidFormat;
        if (text[8] != '-' or text[13] != '-' or text[18] != '-' or text[23] != '-') {
            return error.InvalidFormat;
        }

        var bytes: [16]u8 = undefined;
        var byte_idx: usize = 0;
        var char_idx: usize = 0;
        while (char_idx < text.len) {
            if (text[char_idx] == '-') {
                char_idx += 1;
                continue;
            }
            if (byte_idx == 16 or char_idx + 1 >= text.len) return error.InvalidFormat;
            const hi = hexValue(text[char_idx]) orelse return error.InvalidFormat;
            const lo = hexValue(text[char_idx + 1]) orelse return error.InvalidFormat;
            bytes[byte_idx] = (hi << 4) | lo;
            byte_idx += 1;
            char_idx += 2;
        }
        if (byte_idx != 16) return error.InvalidFormat;

        return .{ .bytes = bytes };
    }

    fn hexValue(c: u8) ?u8 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => null,
        };
    }
};
