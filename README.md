# z-uuid

UUID v4 and v7 for **Zig 0.17.0**, following [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562).
Pure Zig, no dependencies beyond `std`, no heap allocations or global generator state.

[Library API](https://carlos-sweb.github.io/z-uuid/) · [Zig 0.17 standard library API](https://ziglang.org/documentation/0.17.0/std/)

## Install

Run this from your project's directory to install **z-uuid 1.0.0**:

```bash
zig fetch --save=zuuid https://github.com/carlos-sweb/z-uuid/archive/refs/tags/1.0.0.tar.gz
```

Zig adds the dependency URL and package hash to `build.zig.zon`.
Add the module to your executable in `build.zig`:

```zig
const zuuid_dep = b.dependency("zuuid", .{});
exe.root_module.addImport("zuuid", zuuid_dep.module("zuuid"));
```

## Usage

```zig
const std = @import("std");
const Uuid = @import("zuuid").Uuid;

pub fn main(init: std.process.Init) !void {
    const source: std.Random.IoSource = .{ .io = init.io };
    const random = source.interface();

    const id = Uuid.v4(random);
    std.debug.print("{f}\n", .{id});

    const timed = try Uuid.v7(random, init.io);
    var buf: [36]u8 = undefined;
    std.debug.print("{s}\n", .{timed.toString(&buf)});

    var generator: Uuid.V7Generator = .{};
    const first = try generator.next(random, init.io);
    const second = try generator.next(random, init.io);
    std.debug.assert(first.order(second) == .lt);

    const parsed = try Uuid.parse("3f2504e0-4f89-41d3-9a0c-0305e82c3301");
    std.debug.assert(parsed.version() == 4);
}
```

## Features

| Feature | How it works |
|---|---|
| Random UUIDs | `v4(random)` generates a UUID with 122 random bits. |
| Time-ordered UUIDs | `v7(random, io)` embeds Unix time in milliseconds. `v7At(random, unix_ms)` accepts an explicit timestamp. Same-millisecond values have no generation-order guarantee. |
| Monotonic UUIDs | `V7Generator.next(random, io)` and `nextAt(random, unix_ms)` produce strictly increasing UUIDs through sequential calls on one instance, including clock regressions. Counter exhaustion advances the issued timestamp; it may run ahead of the clock. |
| Parsing | `parse(text)` accepts the 36-character `8-4-4-4-12` format with uppercase, lowercase, or mixed-case hex. It validates syntax, without checking version or variant. |
| Formatting | `toString(&buf)` writes 36 lowercase characters without a NUL terminator. `{f}` prints a UUID directly and propagates writer errors. |
| Comparison | `eql(other)` compares all 16 bytes. `order(other)` returns `.lt`, `.eq`, or `.gt`; v7 timestamps are compared first. |
| Inspection | `version()` reads the version nibble. `bytes` exposes the mutable 16-byte RFC big-endian representation. |

### Contract

- Supply the random source and keep it alive while using its interface. Use a CSPRNG when unpredictability is required; uniqueness is probabilistic.
- The slice returned by `toString` borrows your buffer. Keep it alive and unchanged while using the slice.
- Synchronize access when sharing a generator. Separate or copied instances do not share an ordering guarantee.
- Timestamps must be in `[0, 2^48-1]`; invalid timestamps or generator overflow return `error.InvalidTimestamp` without changing generator state. Invalid text returns `error.InvalidFormat`.

See the [library API](https://carlos-sweb.github.io/z-uuid/) for full signatures and generator details. Seeded generation sequences are not a compatibility guarantee.

## Tests and API documentation

```bash
zig build test
zig build docs
python3 -m http.server -d zig-out/docs 8080
```

`zig build` also runs all tests. Zig generates the API documentation from source comments in `zig-out/docs`; open [localhost:8080](http://localhost:8080) to browse it.
GitHub Actions builds and publishes the [online API](https://carlos-sweb.github.io/z-uuid/) when `main` is updated.

## Benchmarks

Compare the frozen previous implementation with the current code:

```bash
zig build bench -Doptimize=ReleaseFast
```

See the [methodology](benchmarks/README.md) and [measured results](https://github.com/carlos-sweb/z-uuid/blob/1.0.0/benchmarks/results/summary.md).
