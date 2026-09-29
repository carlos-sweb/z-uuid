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

    b.default_step = test_step;
}
