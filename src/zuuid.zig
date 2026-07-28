//! `z-uuid`: UUID v4 (random) and v7 (time-ordered) generation, RFC 9562.
pub const Uuid = @import("uuid.zig").Uuid;

test {
    _ = @import("uuid.zig");
}
