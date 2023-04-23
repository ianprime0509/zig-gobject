const std = @import("std");

const modules = [_][]const u8{
    "adw-1",
    "atk-1.0",
    "cairo-1.0",
    "fontconfig-2.0",
    "freetype2-2.0",
    "gdk-3.0",
    "gdk-4.0",
    "gdkpixbuf-2.0",
    "gdkpixdata-2.0",
    "gdkwayland-4.0",
    // "gdkwin32-4.0", // TODO: platform-specific tests
    "gdkx11-3.0",
    "gdkx11-4.0",
    "gio-2.0",
    "gl-1.0",
    "glib-2.0",
    "gmodule-2.0",
    "gobject-2.0",
    "graphene-1.0",
    "gsk-4.0",
    "gtk-3.0",
    "gtk-4.0",
    "harfbuzz-0.0",
    "libxml2-2.0",
    "pango-1.0",
    "pangocairo-1.0",
    "pangofc-1.0",
    "pangoft2-1.0",
    "pangoot-1.0",
    "pangoxft-1.0",
    "vulkan-1.0",
    "win32-1.0",
    "xfixes-4.0",
    "xft-2.0",
    "xlib-2.0",
    "xrandr-1.3",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bindings = b.dependency("zig-gobject", .{});

    const test_step = b.step("test", "Run binding tests");

    for (modules) |module| {
        const dash_index = std.mem.indexOfScalar(u8, module, '-').?;
        const local_name = module[0..dash_index];
        const tests = b.addTest(.{
            .root_source_file = .{ .path = b.fmt("{s}.zig", .{module}) },
            .target = target,
            .optimize = optimize,
        });
        tests.addModule(local_name, bindings.module(module));
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
