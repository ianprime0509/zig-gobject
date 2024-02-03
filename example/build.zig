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
    exe.root_module.addImport("glib", gobject.module("glib-2.0"));
    exe.root_module.addImport("gobject", gobject.module("gobject-2.0"));
    exe.root_module.addImport("gio", gobject.module("gio-2.0"));
    exe.root_module.addImport("cairo", gobject.module("cairo-1.0"));
    exe.root_module.addImport("pango", gobject.module("pango-1.0"));
    exe.root_module.addImport("pangocairo", gobject.module("pangocairo-1.0"));
    exe.root_module.addImport("gdk", gobject.module("gdk-4.0"));
    exe.root_module.addImport("gtk", gobject.module("gtk-4.0"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&run_cmd.step);
}
