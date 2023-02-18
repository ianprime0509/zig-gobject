const std = @import("std");
const libxml2 = @import("lib/zig-libxml2/libxml2.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libxml2_lib = try libxml2.create(b, target, optimize, .{
        .iconv = false,
        .lzma = false,
        .sax1 = true,
        .zlib = false,
    });

    const exe = b.addExecutable(.{
        .name = "zig-gobject",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    libxml2_lib.link(exe);
    exe.install();

    const run_cmd = b.addRunArtifact(exe);
    // See https://github.com/ziglang/zig/issues/14666
    run_cmd.condition = .always;
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    const example_exe = b.addExecutable(.{
        .name = "zig-gobject-example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    example_exe.linkLibC();
    example_exe.linkSystemLibrary("gtk4");

    const example_build_step = b.step("example-build", "Build the example");
    example_build_step.dependOn(&example_exe.step);

    const example_run_cmd = b.addRunArtifact(example_exe);
    example_run_cmd.condition = .always;
    example_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        example_run_cmd.addArgs(args);
    }

    const example_run_step = b.step("example-run", "Run the example");
    example_run_step.dependOn(&example_run_cmd.step);
}
