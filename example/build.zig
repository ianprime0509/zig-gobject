const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig-gobject-examples",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("glib", gobject.module("glib2"));
    exe.root_module.addImport("gobject", gobject.module("gobject2"));
    exe.root_module.addImport("gio", gobject.module("gio2"));
    exe.root_module.addImport("cairo", gobject.module("cairo1"));
    exe.root_module.addImport("pango", gobject.module("pango1"));
    exe.root_module.addImport("pangocairo", gobject.module("pangocairo1"));
    exe.root_module.addImport("gdk", gobject.module("gdk4"));
    exe.root_module.addImport("gtk", gobject.module("gtk4"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&run_cmd.step);
}
