const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "bittorrent_zig", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.installArtifact(exe);

    const exec_check = b.addExecutable(.{ .name = "bittorrent_zig", .root_module = exe.root_module });
    const check_step = b.step("check", "Check if code compiles");
    check_step.dependOn(&exec_check.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const exe_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("tests.zig"), .target = target, .optimize = optimize }), .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple } });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
    b.installArtifact(exe_tests);
}
