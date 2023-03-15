const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bindings = b.dependency("zig-gobject", .{});

    const exe = b.addExecutable(.{
        .name = "zig-gobject-examples",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("glib-2.0", bindings.module("glib-2.0"));
    exe.addModule("gobject-2.0", bindings.module("gobject-2.0"));
    exe.addModule("gio-2.0", bindings.module("gio-2.0"));
    exe.addModule("cairo-1.0", bindings.module("cairo-1.0"));
    exe.addModule("gdk-4.0", bindings.module("gdk-4.0"));
    exe.addModule("gtk-4.0", bindings.module("gtk-4.0"));
    exe.install();

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&run_cmd.step);
}
