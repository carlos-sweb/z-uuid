const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zuuid_module = b.addModule("zuuid", .{
        .root_source_file = b.path("src/zuuid.zig"),
    });

    const docs_mod = b.createModule(.{
        .root_source_file = b.path("src/zuuid.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const docs_lib = b.addLibrary(.{
        .name = "zuuid",
        .root_module = docs_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate autodocs (zig-out/docs)");
    docs_step.dependOn(&install_docs.step);

    const test_step = b.step("test", "Run all tests");

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zuuid.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/uuid_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("zuuid", zuuid_module);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const comparison_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/correctness.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zuuid", .module = zuuid_module }},
        }),
    });
    test_step.dependOn(&b.addRunArtifact(comparison_tests).step);
    const check = b.step("check", "Compile all tests without executing (for cross-target checks)");
    check.dependOn(&lib_tests.step);
    check.dependOn(&unit_tests.step);
    check.dependOn(&comparison_tests.step);

    const bench = b.addExecutable(.{
        .name = "uuid-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zuuid", .module = zuuid_module }},
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    run_bench.addPassthruArgs();
    b.step("bench", "Compare frozen and current UUID implementations (use -Doptimize=ReleaseFast)").dependOn(&run_bench.step);

    const behavior = b.addExecutable(.{
        .name = "uuid-behavior",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/behavior.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zuuid", .module = zuuid_module }},
        }),
    });
    const run_behavior = b.addRunArtifact(behavior);
    run_behavior.addPassthruArgs();
    b.step("bench-behavior", "Count RNG calls and fixed-clock timestamp drift").dependOn(&run_behavior.step);

    const SizeVariant = enum { old, current, order128, order64, parse_fixed, parse_table, hex_pairs, grouped, grouped_policy };
    const size_variant = b.option(SizeVariant, "size-variant", "Implementation for uniform code-size wrappers") orelse .current;
    const size_options = b.addOptions();
    size_options.addOption(SizeVariant, "variant", size_variant);
    const size_module = b.createModule(.{
        .root_source_file = b.path("benchmarks/size.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zuuid", .module = zuuid_module },
            .{ .name = "candidates", .module = b.createModule(.{ .root_source_file = b.path("benchmarks/candidates.zig") }) },
        },
    });
    size_module.addOptions("size_options", size_options);
    const size_object = b.addObject(.{ .name = "uuid-size", .root_module = size_module });
    const install_size = b.addInstallFileWithDir(size_object.getEmittedBin(), .prefix, b.fmt("benchmarks/size-{s}.o", .{@tagName(size_variant)}));
    b.step("bench-size", "Emit uniform wrappers for code-size comparison").dependOn(&install_size.step);

    b.default_step = test_step;
}
