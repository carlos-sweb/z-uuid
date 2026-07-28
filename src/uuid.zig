//! UUID v4 (random) and v7 (time-ordered), per RFC 9562.
const std = @import("std");

const hex_chars = "0123456789abcdef";

/// A 128-bit UUID, stored in the same big-endian byte layout the RFC
/// uses for its canonical string form -- `bytes[6]`'s high nibble is
/// always the version, `bytes[8]`'s top two bits are always the variant
/// (`10`), regardless of which constructor produced it.
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

    /// Time-ordered UUID (RFC 9562 §5.7) using the current wall clock.
    /// Zig 0.16 routes both the clock and the CSPRNG through `std.Io`
    /// (see `std.Io.Clock`/`std.Random.IoSource`) rather than exposing
    /// `std.time.milliTimestamp`/`std.crypto.random` globals, so `io` is
    /// required here (unlike `v4`, which only needs `random`).
    pub fn v7(random: std.Random, io: std.Io) Uuid {
        const ts = std.Io.Clock.real.now(io);
        const unix_ms: i64 = @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_ms));
        return v7At(random, unix_ms);
    }

    /// Same as `v7`, but with an explicit millisecond timestamp instead
    /// of reading the wall clock -- lets callers (and tests) produce
    /// deterministic, reproducible UUIDs.
    pub fn v7At(random: std.Random, unix_ms: i64) Uuid {
        var bytes: [16]u8 = undefined;
        const ts: u48 = @intCast(unix_ms);
        bytes[0] = @truncate(ts >> 40);
        bytes[1] = @truncate(ts >> 32);
        bytes[2] = @truncate(ts >> 24);
        bytes[3] = @truncate(ts >> 16);
        bytes[4] = @truncate(ts >> 8);
        bytes[5] = @truncate(ts);

        random.bytes(bytes[6..16]);
        bytes[6] = 0x70 | (bytes[6] & 0x0F);
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
