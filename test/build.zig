const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bindings = b.dependency("zig-gobject", .{});

    const test_step = b.step("test", "Run binding tests");

    const gobject2_tests = b.addTest(.{
        .root_source_file = .{ .path = "gobject-2.0.zig" },
        .target = target,
        .optimize = optimize,
    });
    gobject2_tests.addModule("gobject", bindings.module("gobject-2.0"));
    test_step.dependOn(&gobject2_tests.step);
}
