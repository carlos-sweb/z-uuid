//! UUID v4 (random) and v7 (time-ordered), per RFC 9562.
const std = @import("std");

const hex_chars = "0123456789abcdef";

/// A 128-bit UUID in the RFC 9562 big-endian byte layout.
/// `v4`, `v7`, and `v7At` stamp the version nibble and RFC variant `10`.
/// `parse` copies the canonical hex form as-is and does not rewrite those
/// fields, so a parsed value can carry any version or variant.
pub const Uuid = struct {
    bytes: [16]u8,

    /// Random UUID (RFC 9562 §5.4): 122 bits of CSPRNG output, version
    /// nibble `0100` and variant bits `10` stamped over the rest.
    pub fn v4(random: std.Random) Uuid {
        var bytes: [16]u8 = undefined;
        random.bytes(&bytes);
        bytes[6] = 0x40 | (bytes[6] & 0x0F);
        bytes[8] = 0x80 | (bytes[8] & 0x3F);
        return .{ .bytes = bytes };
    }

    pub const TimestampError = error{InvalidTimestamp};

    /// Time-ordered UUID (RFC 9562 §5.7) using the current wall clock.
    /// Zig 0.16 routes both the clock and the CSPRNG through `std.Io`
    /// (see `std.Io.Clock`/`std.Random.IoSource`) rather than exposing
    /// `std.time.milliTimestamp`/`std.crypto.random` globals, so `io` is
    /// required here (unlike `v4`, which only needs `random`).
    ///
    /// Returns `error.InvalidTimestamp` if the wall clock is outside the
    /// RFC 48-bit Unix-millisecond range `[0, 2^48-1]`.
    pub fn v7(random: std.Random, io: std.Io) TimestampError!Uuid {
        const ts = std.Io.Clock.real.now(io);
        const unix_ms = std.math.cast(i64, @divFloor(ts.nanoseconds, std.time.ns_per_ms)) orelse
            return error.InvalidTimestamp;
        return v7At(random, unix_ms);
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
    /// - New wall-clock millisecond: reseed `seq` from `random`.
    /// - Same millisecond, or a clock regression: freeze the issued
    ///   timestamp and increment `seq`.
    /// - `seq` exhausted (`2^12` IDs): bump the issued millisecond by 1
    ///   and reseed, so ordering never wraps. Fails with
    ///   `error.InvalidTimestamp` if that bump would exceed `2^48-1`.
    pub const V7Generator = struct {
        last_ms: ?u48 = null,
        seq: u12 = 0,

        /// Like `Uuid.v7`, but monotonic across calls on this generator.
        pub fn next(self: *V7Generator, random: std.Random, io: std.Io) TimestampError!Uuid {
            const ts = std.Io.Clock.real.now(io);
            const unix_ms = std.math.cast(i64, @divFloor(ts.nanoseconds, std.time.ns_per_ms)) orelse
                return error.InvalidTimestamp;
            return self.nextAt(random, unix_ms);
        }

        /// Like `Uuid.v7At`, but monotonic across calls on this generator.
        pub fn nextAt(self: *V7Generator, random: std.Random, unix_ms: i64) TimestampError!Uuid {
            const ts = std.math.cast(u48, unix_ms) orelse return error.InvalidTimestamp;

            var issued_ms: u48 = ts;
            if (self.last_ms) |last| {
                if (ts > last) {
                    self.seq = random.int(u12);
                } else {
                    issued_ms = last;
                    if (self.seq == std.math.maxInt(u12)) {
                        if (last == std.math.maxInt(u48)) return error.InvalidTimestamp;
                        issued_ms = last + 1;
                        self.seq = random.int(u12);
                    } else {
                        self.seq += 1;
                    }
                }
            } else {
                self.seq = random.int(u12);
            }

            self.last_ms = issued_ms;
            return fromV7Parts(issued_ms, self.seq, random);
        }
    };

    fn fromV7Parts(ts: u48, rand_a: u12, random: std.Random) Uuid {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u48, bytes[0..6], ts, .big);
        bytes[6] = 0x70 | @as(u8, @truncate(rand_a >> 8));
        bytes[7] = @truncate(rand_a);
        random.bytes(bytes[8..16]);
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
        return std.mem.order(u8, &a.bytes, &b.bytes);
    }

    /// Formats into the canonical lowercase `8-4-4-4-12` dashed form
    /// without allocating.
    pub fn toString(self: Uuid, buf: *[36]u8) []const u8 {
        var i: usize = 0;
        var pos: usize = 0;
        for (self.bytes) |byte| {
            if (pos == 4 or pos == 6 or pos == 8 or pos == 10) {
                buf[i] = '-';
                i += 1;
            }
            buf[i] = hex_chars[byte >> 4];
            buf[i + 1] = hex_chars[byte & 0x0F];
            i += 2;
            pos += 1;
        }
        return buf[0..i];
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
