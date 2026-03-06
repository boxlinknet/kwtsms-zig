const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module (for consumers via build.zig.zon)
    const kwtsms_mod = b.addModule("kwtsms", .{
        .root_source_file = b.path("src/kwtsms.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "kwtsms",
        .root_source_file = b.path("src/kwtsms.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/kwtsms.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Integration tests (separate step, requires credentials)
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("src/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("kwtsms", kwtsms_mod);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_step = b.step("test-integration", "Run integration tests (requires ZIG_USERNAME/ZIG_PASSWORD)");
    integration_step.dependOn(&run_integration_tests.step);

    // Example
    const example = b.addExecutable(.{
        .name = "kwtsms-example",
        .root_source_file = b.path("examples/01_basic_usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("kwtsms", kwtsms_mod);
    b.installArtifact(example);
}
