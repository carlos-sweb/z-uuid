# z-uuid

UUID generation for Zig — currently **v4** (random) and **v7** (time-ordered),
per [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562). Pure Zig, zero
dependencies beyond `std`.

Requires **Zig 0.17.0**. The library is independent of its consumers:
it defines UUID values and generation, parsing, formatting, and ordering
operations without application-specific namespaces or runtime bindings.

```bash
zig build              # runs the tests (default step)
zig build test
```

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

    // The caller supplies the random source and the clock through std.Io.
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
  by the caller). `next(random, io)` / `nextAt(random, unix_ms)` both return
  `error{InvalidTimestamp}!Uuid`
- `Uuid.parse(text: []const u8) error{InvalidFormat}!Uuid` — canonical
  lowercase-or-uppercase `8-4-4-4-12` dashed form only; does not rewrite
  version or variant bits
- `Uuid.toString(self, buf: *[36]u8) []const u8` — no-alloc formatter
- `Uuid.format` — so `{f}`/`std.debug.print` work directly on a `Uuid`
- `Uuid.version(self) u4`
- `Uuid.eql(a, b) bool`
- `Uuid.order(a, b) std.math.Order` — lexicographic on RFC bytes; for v7
  this compares the embedded timestamps first

The caller always supplies the `std.Random` source explicitly (e.g. via
`std.Random.IoSource{ .io = io }.interface()`, or a seeded
`std.Random.DefaultPrng` in tests). The quality and unpredictability of
generated IDs depend on that source; use a CSPRNG when unpredictability
is required. Keep the source alive while using its `std.Random` interface.

## Contract and ownership

- `Uuid.bytes` contains 16 bytes in RFC big-endian layout. It is publicly
  mutable; callers are responsible for any changes. `parse` checks textual
  syntax, accepting mixed-case hex, without validating version or variant.
- The library allocates no heap memory and keeps no global generator state.
  `toString` returns a 36-byte lowercase slice borrowing the supplied buffer,
  without a NUL terminator. Keep the buffer alive and unchanged while using
  that slice. `format` propagates `std.Io.Writer.Error`.
- Stateless `v7`/`v7At` order by timestamp across different milliseconds;
  values within the same millisecond have no generation-order guarantee.
- `V7Generator` guarantees strictly increasing UUIDs for sequential calls
  on one instance. It has no internal synchronization: sharing an instance
  requires caller synchronization. Separate or copied instances do not
  share an ordering guarantee.
- The generator freezes its issued timestamp on clock regression. When the
  12-bit counter, seeded with 11 random low bits and a zero high bit, is
  exhausted, it advances the issued timestamp by one millisecond and reseeds.
  A newly seeded timestamp accommodates at least 2049 IDs before exhaustion.
  This can happen before 4096 calls and can place the issued timestamp ahead
  of wall-clock time.
- Timestamps outside `[0, 2^48-1]`, including a generator increment beyond
  the upper bound, return `error.InvalidTimestamp`. A failed generator call
  leaves its state unchanged. UUID uniqueness is probabilistic, not a global
  coordination guarantee.

## Performance comparison

The benchmark retains the previous implementation as a frozen reference and
compares it with the current code using Zig 0.17.0. Both remain independent of
applications that consume the library.

```bash
zig build bench -Doptimize=ReleaseFast
zig build bench -Doptimize=ReleaseFast -- --json
python3 benchmarks/run.py --suite final
python3 benchmarks/report.py --suite final
zig build check -Dtarget=aarch64-linux -Doptimize=ReleaseFast
```

See [benchmark methodology](benchmarks/README.md) for workloads, raw samples,
confidence intervals, and acceptance criteria. Complete three-session runs take
several minutes. Cross-compilation checks compatibility, not performance.

Generation sequences for a fixed PRNG seed are not a compatibility guarantee.
The generator now seeds only its low 11 counter bits to leave rollover headroom;
UUID layout, public signatures and error types remain the same.
