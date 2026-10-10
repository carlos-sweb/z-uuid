//! Count RNG calls and timestamp drift outside the speed measurement harness.
const std = @import("std");
const Old = @import("baseline/uuid.zig").Uuid;
const New = @import("zuuid").Uuid;
const Counted = struct {
    prng: std.Random.DefaultPrng = .init(0x1709562),
    calls: usize = 0,
    bytes: usize = 0,
    fn fill(self: *Counted, buf: []u8) void {
        self.calls += 1;
        self.bytes += buf.len;
        self.prng.random().bytes(buf);
    }
    fn random(self: *Counted) std.Random {
        return .init(self, fill);
    }
};
fn report(comptime U: type, name: []const u8, writer: *std.Io.Writer) !void {
    var source: Counted = .{};
    const random = source.random();
    for (0..100_000) |_| std.mem.doNotOptimizeAway(try U.v7At(random, 1000));
    const stateless_calls = source.calls;
    const stateless_bytes = source.bytes;
    source = .{};
    var generator: U.V7Generator = .{};
    var issued: ?u48 = null;
    var reseeds: usize = 0;
    for (0..100_000) |_| {
        const value = try generator.nextAt(random, 1000);
        const timestamp = std.mem.readInt(u48, value.bytes[0..6], .big);
        if (issued == null or issued.? != timestamp) reseeds += 1;
        issued = timestamp;
        std.mem.doNotOptimizeAway(&value);
    }
    try writer.print("{{\"version\":\"{s}\",\"ids\":100000,\"stateless_rng_calls\":{d},\"stateless_rng_bytes\":{d},\"generator_rng_calls\":{d},\"generator_rng_bytes\":{d},\"generator_reseeds\":{d},\"fixed_clock_ahead_ms\":{d}}}\n", .{ name, stateless_calls, stateless_bytes, source.calls, source.bytes, reseeds, issued.? - 1000 });
}
pub fn main(init: std.process.Init) !void {
    var buffer: [2048]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try report(Old, "old", &output.interface);
    try report(New, "current", &output.interface);
    try output.interface.flush();
}
