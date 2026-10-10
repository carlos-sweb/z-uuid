//! Reproducible paired microbenchmarks; no application or runtime bindings.
const std = @import("std");
const builtin = @import("builtin");
const Old = @import("baseline/uuid.zig").Uuid;
const New = @import("zuuid").Uuid;
const c = @import("candidates.zig");
const provenance = @embedFile("baseline/provenance.json");
const Variant = enum { old, current, order128, order64, parse_fixed, parse_table, hex_pairs, grouped, grouped_policy };
const Work = enum {
    v4,
    v7_at,
    v7_clock,
    next_fixed,
    next_increasing,
    next_regression,
    next_overflow,
    next_clock,
    order_v4,
    order_v7,
    order_equal,
    order_last,
    eql,
    version,
    string,
    format,
    parse_lower,
    parse_upper,
    parse_mixed,
    parse_invalid_early,
    parse_invalid_late,
    parse_invalid_dash,
    parse_invalid_length,
    v4_string,
    v7_string,
    sort_v4,
    sort_v7,
};
const Source = enum { prng, io };
const dataset_len = 1024;
const sample_count = 20;
const seed = 0x1709562;
var sink: u64 = 0;

const Dataset = struct {
    ids: [dataset_len]Old,
    other: [dataset_len]Old,
    texts: [dataset_len][36]u8,
    fn init(work: Work) Dataset {
        var result: Dataset = undefined;
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        for (&result.ids, &result.other, &result.texts, 0..) |*a, *b, *text, i| {
            a.* = switch (work) {
                .order_v7, .sort_v7 => Old.v7At(random, 1_700_000_000_000 + @as(i64, @intCast(i % 8))) catch unreachable,
                else => Old.v4(random),
            };
            b.* = switch (work) {
                .order_v7 => Old.v7At(random, 1_700_000_000_000 + @as(i64, @intCast(i % 8))) catch unreachable,
                .order_equal => a.*,
                .order_last => blk: {
                    var value = a.*;
                    value.bytes[15] ^= 1;
                    break :blk value;
                },
                else => Old.v4(random),
            };
            _ = a.toString(text);
            switch (work) {
                .parse_upper => for (text) |*byte| {
                    byte.* = std.ascii.toUpper(byte.*);
                },
                .parse_mixed => for (text, 0..) |*byte, p| {
                    if (p % 2 == 0) byte.* = std.ascii.toUpper(byte.*);
                },
                .parse_invalid_early => text[0] = '!',
                .parse_invalid_late => text[35] = '!',
                .parse_invalid_dash => text[13] = '_',
                else => {},
            }
        }
        return result;
    }
};

fn Uuid(comptime variant: Variant) type {
    return if (variant == .current) New else Old;
}
fn Generator(comptime variant: Variant) type {
    return switch (variant) {
        .current => New.V7Generator,
        .grouped => c.Generator(false),
        .grouped_policy => c.Generator(true),
        else => Old.V7Generator,
    };
}
fn compare(comptime variant: Variant, a: Old, b: Old) std.math.Order {
    return switch (variant) {
        .current => (New{ .bytes = a.bytes }).order(.{ .bytes = b.bytes }),
        .order128 => c.order128(a, b),
        .order64 => c.order64(a, b),
        else => a.order(b),
    };
}
fn string(comptime variant: Variant, value: Uuid(variant), buf: *[36]u8) []const u8 {
    return if (variant == .hex_pairs) c.toString(value, buf) else value.toString(buf);
}
fn stateless(comptime variant: Variant, random: std.Random, ms: i64) !Uuid(variant) {
    return if (variant == .grouped or variant == .grouped_policy) c.v7At(random, ms) else Uuid(variant).v7At(random, ms);
}
fn parse(comptime variant: Variant, text: []const u8) !Uuid(variant) {
    return switch (variant) {
        .parse_fixed => c.parse(false, text),
        .parse_table => c.parse(true, text),
        else => Uuid(variant).parse(text),
    };
}
fn consume(value: anytype) u64 {
    // The pointer barrier makes all 16 result bytes observable to the optimizer.
    std.mem.doNotOptimizeAway(&value);
    return std.mem.readInt(u64, value.bytes[8..16], .little);
}

fn kernel(comptime variant: Variant, comptime work: Work, n: usize, data: *const Dataset, random: std.Random, io: std.Io, generator: *Generator(variant)) u64 {
    var checksum: u64 = 0;
    var buf: [36]u8 = undefined;
    if (work == .sort_v4 or work == .sort_v7) {
        var scratch: [dataset_len]Old = undefined;
        const Context = struct {
            fn less(_: void, a: Old, b: Old) bool {
                return compare(variant, a, b) == .lt;
            }
        };
        for (0..n / dataset_len) |_| {
            // Copy is necessary to sort the same unsorted input each time;
            // both variants include this identical cost.
            scratch = data.ids;
            std.mem.sort(Old, &scratch, {}, Context.less);
            std.mem.doNotOptimizeAway(&scratch);
            checksum +%= consume(scratch[dataset_len / 2]);
        }
        return checksum;
    }
    for (0..n) |i| {
        const index = i & (dataset_len - 1);
        const a = data.ids[index];
        const b = data.other[index];
        switch (work) {
            .v4 => checksum +%= consume(Uuid(variant).v4(random)),
            .v7_at => checksum +%= consume(stateless(variant, random, 1_700_000_000_000 + @as(i64, @intCast(index))) catch unreachable),
            .v7_clock => {
                const value = if (variant == .grouped or variant == .grouped_policy) c.v7(random, io) catch unreachable else Uuid(variant).v7(random, io) catch unreachable;
                checksum +%= consume(value);
            },
            .next_fixed, .next_increasing, .next_regression, .next_overflow => {
                const ms: i64 = switch (work) {
                    .next_increasing => 1_700_000_000_000 + @as(i64, @intCast(i)),
                    .next_regression => 1_700_000_000_000 - @as(i64, @intCast(index)),
                    .next_overflow => blk: {
                        generator.last_ms = 1_700_000_000_000 + @as(u48, @intCast(i));
                        generator.seq = 4095;
                        break :blk @intCast(generator.last_ms.?);
                    },
                    else => 1_700_000_000_000,
                };
                checksum +%= consume(generator.nextAt(random, ms) catch unreachable);
            },
            .next_clock => checksum +%= consume(generator.next(random, io) catch unreachable),
            .order_v4, .order_v7, .order_equal, .order_last => {
                std.mem.doNotOptimizeAway(&a);
                std.mem.doNotOptimizeAway(&b);
                checksum +%= @backingInt(compare(variant, a, b));
            },
            .eql => {
                std.mem.doNotOptimizeAway(&a);
                std.mem.doNotOptimizeAway(&b);
                checksum +%= @intFromBool((Uuid(variant){ .bytes = a.bytes }).eql(.{ .bytes = b.bytes }));
            },
            .version => {
                std.mem.doNotOptimizeAway(&a);
                checksum +%= (Uuid(variant){ .bytes = a.bytes }).version();
            },
            .string, .format => {
                const value: Uuid(variant) = .{ .bytes = a.bytes };
                std.mem.doNotOptimizeAway(&value);
                if (work == .format) {
                    var writer: std.Io.Writer = .fixed(&buf);
                    if (variant == .hex_pairs) {
                        var text: [36]u8 = undefined;
                        writer.writeAll(string(variant, value, &text)) catch unreachable;
                    } else value.format(&writer) catch unreachable;
                } else {
                    _ = string(variant, value, &buf);
                }
                std.mem.doNotOptimizeAway(&buf);
                checksum +%= buf[i % 36];
            },
            .parse_lower, .parse_upper, .parse_mixed, .parse_invalid_early, .parse_invalid_late, .parse_invalid_dash, .parse_invalid_length => {
                const len: usize = if (work == .parse_invalid_length) 35 else 36;
                const text = data.texts[index][0..len];
                std.mem.doNotOptimizeAway(text.ptr);
                const result = parse(variant, text) catch {
                    checksum +%= 1;
                    continue;
                };
                checksum +%= consume(result);
            },
            .v4_string, .v7_string => {
                const value = if (work == .v4_string) Uuid(variant).v4(random) else stateless(variant, random, 1_700_000_000_000 + @as(i64, @intCast(index))) catch unreachable;
                _ = string(variant, value, &buf);
                std.mem.doNotOptimizeAway(&buf);
                checksum +%= buf[i % 36];
            },
            .sort_v4, .sort_v7 => unreachable,
        }
    }
    return checksum;
}

fn measure(comptime variant: Variant, comptime work: Work, comptime source: Source, n: usize, data: *const Dataset, io: std.Io) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const io_source: std.Random.IoSource = .{ .io = io };
    const random = if (source == .prng) prng.random() else io_source.interface();
    var generator: Generator(variant) = .{};
    const start = std.Io.Clock.awake.now(io);
    const result = kernel(variant, work, n, data, random, io, &generator);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    sink +%= result;
    std.mem.doNotOptimizeAway(&sink);
    return @floatFromInt(elapsed);
}
fn sortedMedian(input: []const f64) f64 {
    var copy: [sample_count]f64 = undefined;
    @memcpy(copy[0..input.len], input);
    std.mem.sort(f64, copy[0..input.len], {}, std.sort.asc(f64));
    return (copy[input.len / 2 - 1] + copy[input.len / 2]) / 2;
}
fn interval(old: []const f64, new: []const f64) [2]f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    var ratios: [2000]f64 = undefined;
    for (&ratios) |*ratio| {
        var a: [sample_count]f64 = undefined;
        var b: [sample_count]f64 = undefined;
        for (&a, &b) |*x, *y| {
            const i = prng.random().uintLessThan(usize, sample_count);
            x.* = old[i];
            y.* = new[i];
        }
        ratio.* = sortedMedian(&a) / sortedMedian(&b);
    }
    std.mem.sort(f64, &ratios, {}, std.sort.asc(f64));
    return .{ ratios[50], ratios[1949] };
}
fn isGeneration(work: Work) bool {
    return switch (work) {
        .v4, .v7_at, .v7_clock, .next_fixed, .next_increasing, .next_regression, .next_overflow, .next_clock, .v4_string, .v7_string => true,
        else => false,
    };
}
fn applicable(variant: Variant, work: Work) bool {
    return switch (variant) {
        .old => false,
        .current => true,
        .order128, .order64 => switch (work) {
            .order_v4, .order_v7, .order_equal, .order_last, .sort_v4, .sort_v7 => true,
            else => false,
        },
        .parse_fixed, .parse_table => switch (work) {
            .parse_lower, .parse_upper, .parse_mixed, .parse_invalid_early, .parse_invalid_late, .parse_invalid_dash, .parse_invalid_length => true,
            else => false,
        },
        .hex_pairs => switch (work) {
            .string, .format, .v4_string, .v7_string => true,
            else => false,
        },
        .grouped, .grouped_policy => switch (work) {
            .v7_at, .v7_clock, .next_fixed, .next_increasing, .next_regression, .next_overflow, .next_clock, .v7_string => true,
            else => false,
        },
    };
}
const Options = struct {
    json: bool = false,
    candidates: bool = false,
    filter: []const u8 = "",
    min_ms: u64 = 100,
};
fn calibrate(comptime variant: Variant, comptime work: Work, comptime source: Source, minimum: f64, data: *const Dataset, io: std.Io) !usize {
    var n: usize = dataset_len;
    while (true) {
        const elapsed = measure(variant, work, source, n, data, io);
        if (elapsed >= minimum) return n;
        // Include 10% headroom, rounded to full dataset cycles.
        const estimate = @as(f64, @floatFromInt(n)) * minimum / @max(elapsed, 1) * 1.1;
        if (estimate >= @as(f64, @floatFromInt(std.math.maxInt(usize) / 2))) return error.CalibrationOverflow;
        const target: usize = @intFromFloat(estimate);
        n = @max(n + dataset_len, std.mem.alignForward(usize, target, dataset_len));
    }
}
fn run(comptime variant: Variant, comptime work: Work, comptime source: Source, options: Options, io: std.Io, writer: *std.Io.Writer) !void {
    const name = @tagName(work) ++ "/" ++ @tagName(source);
    if (options.filter.len != 0 and std.mem.indexOf(u8, name, options.filter) == null) return;
    const data = Dataset.init(work);
    const minimum: f64 = @floatFromInt(options.min_ms * std.time.ns_per_ms);
    // Calibrate each version independently. Otherwise a 5x faster candidate
    // forces every baseline sample to run 5x longer than the requested window.
    // Both versions cycle the same dataset, reset state and normalize per op.
    const old_n = try calibrate(.old, work, source, minimum, &data, io);
    const new_n = try calibrate(variant, work, source, minimum, &data, io);
    for (0..3) |_| {
        _ = measure(.old, work, source, old_n, &data, io);
        _ = measure(variant, work, source, new_n, &data, io);
    }
    var old: [sample_count]f64 = undefined;
    var new: [sample_count]f64 = undefined;
    for (0..sample_count) |i| {
        if (i % 2 == 0) {
            old[i] = measure(.old, work, source, old_n, &data, io);
            new[i] = measure(variant, work, source, new_n, &data, io);
        } else {
            new[i] = measure(variant, work, source, new_n, &data, io);
            old[i] = measure(.old, work, source, old_n, &data, io);
        }
        old[i] /= @floatFromInt(old_n);
        new[i] /= @floatFromInt(new_n);
    }
    const old_median = sortedMedian(&old);
    const new_median = sortedMedian(&new);
    const ci = interval(&old, &new);
    const speedup = old_median / new_median;
    if (options.json) {
        try writer.print("{{\"type\":\"case\",\"variant\":\"{s}\",\"work\":\"{s}\",\"source\":\"{s}\",\"old_iterations\":{d},\"new_iterations\":{d},\"old_ns\":{d},\"new_ns\":{d},\"speedup\":{d},\"ci95\":[{d},{d}],\"old_samples\":[", .{ @tagName(variant), @tagName(work), @tagName(source), old_n, new_n, old_median, new_median, speedup, ci[0], ci[1] });
        for (old, 0..) |value, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("{d}", .{value});
        }
        try writer.writeAll("],\"new_samples\":[");
        for (new, 0..) |value, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("{d}", .{value});
        }
        try writer.writeAll("]}\n");
    } else {
        try writer.print("{s: <16} {s: <30} old {d: >9.3} ns  new {d: >9.3} ns  {d:.3}x  CI95 [{d:.3}, {d:.3}]\n", .{ @tagName(variant), name, old_median, new_median, speedup, ci[0], ci[1] });
    }
    try writer.flush();
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    var options: Options = .{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) options.json = true else if (std.mem.eql(u8, arg, "--suite")) {
            const suite = args.next() orelse return error.MissingArgument;
            if (std.mem.eql(u8, suite, "candidates")) options.candidates = true else if (!std.mem.eql(u8, suite, "final")) return error.InvalidSuite;
        } else if (std.mem.eql(u8, arg, "--filter")) options.filter = args.next() orelse return error.MissingArgument else if (std.mem.eql(u8, arg, "--min-ms")) {
            options.min_ms = try std.fmt.parseInt(u64, args.next() orelse return error.MissingArgument, 10);
            if (options.min_ms == 0 or options.min_ms > 60_000) return error.InvalidDuration;
        } else return error.UnknownArgument;
    }
    var output_buffer: [16384]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    const writer = &output.interface;
    // Resolve CPU metadata at runtime; the runner emits OS details externally.
    if (options.json) {
        try writer.print("{{\"type\":\"metadata\",\"zig\":\"{s}\",\"mode\":\"{s}\",\"backend\":\"{s}\",\"arch\":\"{s}\",\"os\":\"{s}\",\"cpu\":\"{s}\",\"samples\":20,\"warmups\":3,\"minimum_ms\":{d},\"dataset\":1024,\"seed\":{d},\"provenance\":{s}}}\n", .{ builtin.zig_version_string, @tagName(builtin.mode), @tagName(builtin.zig_backend), @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), builtin.cpu.model.name, options.min_ms, seed, std.mem.trim(u8, provenance, "\n") });
    } else {
        try writer.print("Zig {s}, {s}, {s}-{s}, CPU {s}; 20 paired samples >= {d}ms, 3 warmups.\n", .{ builtin.zig_version_string, @tagName(builtin.mode), @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), builtin.cpu.model.name, options.min_ms });
    }
    try writer.flush();
    // Prime IoSource before measurements; its entropy is intentionally not reproducible.
    var warm: [64]u8 = undefined;
    init.io.random(&warm);
    inline for (comptime std.meta.tags(Variant)) |variant| {
        if (variant != .old) {
            if ((options.candidates and variant != .current and variant != .grouped_policy) or (!options.candidates and variant == .current)) {
                inline for (comptime std.meta.tags(Work)) |work| {
                    if (comptime applicable(variant, work)) {
                        try run(variant, work, .prng, options, init.io, writer);
                        if (comptime isGeneration(work)) try run(variant, work, .io, options, init.io, writer);
                    }
                }
            }
        }
    }
    if (options.json) try writer.print("{{\"type\":\"sink\",\"value\":{d}}}\n", .{sink});
    try writer.flush();
}
