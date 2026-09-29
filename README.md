# z-uuid

UUID generation for Zig — currently **v4** (random) and **v7** (time-ordered),
per [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562). Pure Zig, zero
dependencies beyond `std`.

**Autodocs:** [carlos-sweb.github.io/z-uuid](https://carlos-sweb.github.io/z-uuid/)

```bash
zig build docs          # writes zig-out/docs
python3 -m http.server -d zig-out/docs 8080
```

## Why v4 and v7

v4 is the classic fully-random UUID. v7 embeds a millisecond Unix
timestamp in its top 48 bits, so v7 values sort chronologically while
staying unpredictable — the shape most databases and distributed systems
actually want an identifier to have today.

## Dependency

```zig
// build.zig.zon
.dependencies = .{
    .zuuid = .{ .path = "../z-uuid" },
},
```

```zig
// build.zig
const zuuid_dep = b.dependency("zuuid", .{});
exe.root_module.addImport("zuuid", zuuid_dep.module("zuuid"));
```

## Usage

```zig
const std = @import("std");
const zuuid = @import("zuuid");
const Uuid = zuuid.Uuid;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Zig 0.16 has no `std.crypto.random`/`std.time.milliTimestamp`
    // globals -- both the CSPRNG and the clock come from `std.Io`.
    const io_source: std.Random.IoSource = .{ .io = io };
    const random = io_source.interface();

    const id = Uuid.v4(random);
    std.debug.print("{f}\n", .{id}); // e.g. 3f2504e0-4f89-41d3-9a0c-0305e82c3301

    const one_shot = try Uuid.v7(random, io);
    var buf: [36]u8 = undefined;
    std.debug.print("{s}\n", .{one_shot.toString(&buf)});

    // Monotonic v7 (RFC 9562 §6.2 Method 1): keep the generator next to
    // the ID stream. Two calls in the same millisecond still sort.
    var gen: Uuid.V7Generator = .{};
    const a = try gen.next(random, io);
    const b = try gen.next(random, io);
    std.debug.assert(a.order(b) == .lt);

    const parsed = try Uuid.parse("3f2504e0-4f89-41d3-9a0c-0305e82c3301");
    std.debug.assert(parsed.version() == 4);
}
```

## API

- `Uuid.v4(random: std.Random) Uuid`
- `Uuid.v7(random: std.Random, io: std.Io) error{InvalidTimestamp}!Uuid` —
  timestamp from `std.Io.Clock.real.now(io)`. Fails if the clock is outside
  the RFC 48-bit Unix-ms range `[0, 2^48-1]`
- `Uuid.v7At(random: std.Random, unix_ms: i64) error{InvalidTimestamp}!Uuid`
  — explicit clock, for deterministic tests (no `io` needed). Stateless:
  `rand_a` is random, so same-millisecond values may sort either way
- `Uuid.V7Generator` — monotonic v7 (12-bit `rand_a` counter, state owned
  by the caller). `next(random, io)` / `nextAt(random, unix_ms)`
- `Uuid.parse(text: []const u8) error{InvalidFormat}!Uuid` — canonical
  lowercase-or-uppercase `8-4-4-4-12` dashed form only; does not rewrite
  version or variant bits
- `Uuid.toString(self, buf: *[36]u8) []const u8` — no-alloc formatter
- `Uuid.format` — so `{f}`/`std.debug.print` work directly on a `Uuid`
- `Uuid.version(self) u4`
- `Uuid.eql(a, b) bool`
- `Uuid.order(a, b) std.math.Order` — lexicographic on RFC bytes; for v7
  this is chronological

The caller always supplies the `std.Random` source explicitly (e.g. via
`std.Random.IoSource{ .io = io }.interface()`, or a seeded
`std.Random.DefaultPrng` in tests) — `z-uuid` doesn't hide a global CSPRNG
singleton.

## Roadmap

`z-uuid` is step 1 of a larger plan: a broader `z-crypto` sibling library
(hashing, AEAD, password hashing, HMAC) is next, followed by wiring both
into `z-run`'s `os` global as a nested `os.crypto.*` namespace (e.g.
`os.crypto.uuid.v4()`). ULID/CUID2/NanoID are candidates for a later
`z-uuid` release but aren't implemented yet.
