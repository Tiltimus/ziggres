const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ziggres = b.addModule("ziggres", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
        .imports = &.{},
    });

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_unit_tests.root_module.addImport("ziggres", ziggres);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_lib_unit_tests.step);
}
