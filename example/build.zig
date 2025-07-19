const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glib", .module = gobject.module("glib2") },
            .{ .name = "gobject", .module = gobject.module("gobject2") },
            .{ .name = "gio", .module = gobject.module("gio2") },
            .{ .name = "cairo", .module = gobject.module("cairo1") },
            .{ .name = "pango", .module = gobject.module("pango1") },
            .{ .name = "pangocairo", .module = gobject.module("pangocairo1") },
            .{ .name = "gdk", .module = gobject.module("gdk4") },
            .{ .name = "gtk", .module = gobject.module("gtk4") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig-gobject-examples",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const exe_run = b.addRunArtifact(exe);
    exe_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        exe_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&exe_run.step);
}
