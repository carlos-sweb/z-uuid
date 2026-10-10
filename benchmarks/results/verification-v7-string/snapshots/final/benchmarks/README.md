# UUID performance comparison

The frozen `baseline/uuid.zig` is a snapshot of the workspace implementation
before optimization, identified by `baseline/provenance.json`. It is never
imported by the public `zuuid` module. `candidates.zig` retains experimental
alternatives even if measurements reject them.

```bash
zig build bench -Doptimize=ReleaseFast
zig build bench -Doptimize=ReleaseFast -- --json
zig build bench -Doptimize=ReleaseFast -- --suite candidates
python3 benchmarks/run.py --suite candidates
python3 benchmarks/report.py --suite candidates
python3 benchmarks/run.py --suite final
python3 benchmarks/report.py --suite final
```

The Python runner invokes three independent processes and keeps JSON Lines
samples and machine metadata in `results/`. There are no Python dependencies.
`--filter order_v7` selects cases by name. `--min-ms 1` is useful for harness
smoke checks; acceptance runs use the default 100 ms. Suites execute serially;
do not run compilers or other CPU-heavy tasks concurrently with measurements.

Each case independently calibrates the old and new iteration counts to at least
100 ms (with 10% headroom), then performs three warmup pairs and 20 measured pairs,
alternating which implementation runs first. Actual sample durations vary with
machine load. Dataset construction, PRNG and generator initialization, output,
and bootstrap statistics are outside timing. Sorts include the same copy of an
unsorted 1024-element dataset and report time per element. Monotonic `.awake`
time is used; v7 functions deliberately still use the real wall clock.

Inputs vary across 1024 prepared entries. Result pointers are exposed to
`std.mem.doNotOptimizeAway` and accumulated checksums are emitted after the run.
Both versions execute equivalent kernels. Stateful cases restart per sample;
forced overflow includes identical state setup on each operation. Formatting
barriers expose all 36 bytes, not just the character used by the checksum.

`DefaultPrng` uses a fixed seed. `IoSource` is primed before measurements but
its entropy is not reproducible. It exercises the default `std.process.Init`
I/O provider on the main thread; these results do not measure contention or
predict other I/O providers' performance.

JSON case records contain raw old/new samples in ns/operation, medians, speedup
(old/new), and a 95% paired bootstrap interval for the ratio of medians (2000
resamples). The report includes operations/second and median absolute deviation.
The runner records CPU, OS, compiler, source hashes, affinity, and command flags;
the executable records CPU target, architecture, optimization mode and backend.

The acceptance policy requires a >=5% median time improvement with CI95 excluding
parity in all three sessions in the primary workload. Any applicable workload
with >3% median time regression in a session rejects that alternative. RNG
batching is evaluated separately for stateless and stateful APIs. The counter
seed policy is a behavioral improvement and is not subject to a speed gate.
This is a conservative policy: noise can reject a promising optimization.

Run `zig build check -Dtarget=aarch64-linux -Doptimize=ReleaseFast` to compile all
correctness tests for aarch64 without executing them. Cross-compilation is not
a measurement of aarch64 performance.

Additional diagnostic commands:

```bash
zig build bench-behavior -Doptimize=ReleaseFast
python3 benchmarks/sizes.py
```

`bench-behavior` counts RNG requests and timestamp advances in a 100,000-ID
fixed-clock burst using a seeded source. It is not a speed measurement.
`sizes.py` compiles identical exported wrappers for all alternatives and counts
`.text` plus `.rodata` with GNU `size`; debug/unwind metadata is excluded. Size
is a comparison for these wrappers, not an assertion about every consumer's
linked binary. It resolves performance ties within 3%.

The `results/superseded/` directory contains an interrupted exploratory run
before independent calibration and the format comparison were corrected. It is
excluded from acceptance decisions. Raw result files are kept in the repository
but excluded from the package manifest.
