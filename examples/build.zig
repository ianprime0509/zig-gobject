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
    exe.addModule("glib", bindings.module("glib-2.0"));
    exe.addModule("gobject", bindings.module("gobject-2.0"));
    exe.addModule("gio", bindings.module("gio-2.0"));
    exe.addModule("cairo", bindings.module("cairo-1.0"));
    exe.addModule("pango", bindings.module("pango-1.0"));
    exe.addModule("pangocairo", bindings.module("pangocairo-1.0"));
    exe.addModule("gdk", bindings.module("gdk-4.0"));
    exe.addModule("gtk", bindings.module("gtk-4.0"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&run_cmd.step);
}
