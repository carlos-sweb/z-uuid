//! Uniform exported wrappers to measure code and read-only data independently
//! of the benchmark harness. No runtime barrier or checksum costs are included.
const std = @import("std");
const c = @import("candidates");
const New = @import("zuuid").Uuid;
const variant = @import("size_options").variant;
const Old = c.Old;
const U = if (variant == .current) New else Old;
const G = switch (variant) {
    .current => New.V7Generator,
    .grouped => c.Generator(false),
    .grouped_policy => c.Generator(true),
    else => Old.V7Generator,
};
export fn uuid_order(a: *const U, b: *const U) i8 {
    const result = switch (variant) {
        .order128 => c.order128(a.*, b.*),
        .order64 => c.order64(a.*, b.*),
        else => a.order(b.*),
    };
    return switch (result) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}
export fn uuid_eql(a: *const U, b: *const U) bool {
    return a.eql(b.*);
}
export fn uuid_version(a: *const U) u8 {
    return a.version();
}
export fn uuid_string(a: *const U, out: *[36]u8) void {
    if (variant == .hex_pairs) {
        _ = c.toString(a.*, out);
    } else {
        _ = a.toString(out);
    }
}
export fn uuid_parse(text: [*]const u8, len: usize, out: *U) bool {
    const result = switch (variant) {
        .parse_fixed => c.parse(false, text[0..len]),
        .parse_table => c.parse(true, text[0..len]),
        else => U.parse(text[0..len]),
    };
    out.* = result catch return false;
    return true;
}
export fn uuid_v4(random: *const std.Random, out: *U) void {
    out.* = U.v4(random.*);
}
export fn uuid_v7_at(random: *const std.Random, ms: i64, out: *U) bool {
    out.* = (if (variant == .grouped or variant == .grouped_policy) c.v7At(random.*, ms) else U.v7At(random.*, ms)) catch return false;
    return true;
}
export fn uuid_next_at(generator: *G, random: *const std.Random, ms: i64, out: *U) bool {
    out.* = generator.nextAt(random.*, ms) catch return false;
    return true;
}
export fn uuid_format(value: *const U, writer: *std.Io.Writer) bool {
    if (variant == .hex_pairs) {
        var text: [36]u8 = undefined;
        writer.writeAll(c.toString(value.*, &text)) catch return false;
    } else {
        value.format(writer) catch return false;
    }
    return true;
}
