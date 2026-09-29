//! `z-uuid`: UUID v4 (random) and v7 (time-ordered) generation, RFC 9562.
//!
//! Import the package as `zuuid` and use `Uuid`:
//! ```
//! const Uuid = @import("zuuid").Uuid;
//! ```
pub const Uuid = @import("uuid.zig").Uuid;

test {
    _ = @import("uuid.zig");
}
