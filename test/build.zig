const std = @import("std");

const modules = [_][]const u8{
    "adw-1",
    // TODO: bit fields exceeding c_uint
    // "appstreamglib-1.0",
    "atk-1.0",
    "atspi-2.0",
    "cairo-1.0",
    "dbus-1.0",
    "dbusglib-1.0",
    "fontconfig-2.0",
    // TODO: bad int32 alias
    // "freetype2-2.0",
    "gcab-1.0",
    // TODO: "not enough type information available"
    // "gck-1",
    // TODO: "not enough type information available"
    // "gck-2",
    "gcr-3",
    "gcr-4",
    "gcrui-3",
    "gdesktopenums-3.0",
    "gdk-3.0",
    "gdk-4.0",
    "gdkpixbuf-2.0",
    "gdkpixdata-2.0",
    "gdkwayland-4.0",
    "gdkx11-3.0",
    "gdkx11-4.0",
    // TODO: instance parameters being translated outside any container context
    // "gee-0.8",
    "geoclue-2.0",
    "gio-2.0",
    "girepository-2.0",
    "gl-1.0",
    "glib-2.0",
    "gmodule-2.0",
    "gobject-2.0",
    "graphene-1.0",
    "gsk-4.0",
    // TODO: "dependency loop" in MemoryCopyFunction (really a Zig bug)
    // TODO: bit fields exceeding c_uint
    // "gst-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstallocators-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstapp-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstaudio-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstbadaudio-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstbase-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstcheck-1.0",
    // TODO: "not enough type information available"
    // "gstcodecs-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstcontroller-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstgl-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstglegl-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstglwayland-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstglx11-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstinsertbin-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstmpegts-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstnet-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstpbutils-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstplay-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstplayer-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstrtp-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstrtsp-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstsdp-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gsttag-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gsttranscoder-1.0",
    // TODO: duplicate bit field
    // "gstvideo-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstvulkan-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstvulkanwayland-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstvulkanxcb-1.0",
    // TODO: can't translate until gst-1.0 is fixed
    // "gstwebrtc-1.0",
    "gtk-3.0",
    "gtk-4.0",
    "gtksource-4",
    "gtksource-5",
    "gudev-1.0",
    "handy-1",
    "harfbuzz-0.0",
    // TODO: name conflicts with T
    // "ibus-1.0",
    // TODO: name conflicts with Class
    // "javascriptcore-4.1",
    // TODO: name conflicts with Class
    // "javascriptcore-6.0",
    "json-1.0",
    "libxml2-2.0",
    "manette-0.2",
    "nice-0.1",
    "notify-0.7",
    "pango-1.0",
    "pangocairo-1.0",
    "pangofc-1.0",
    "pangoft2-1.0",
    "pangoot-1.0",
    "polkit-1.0",
    "rsvg-2.0",
    "secret-1",
    "soup-3.0",
    // TODO: can't find the package to install to link this
    // "tracker-3.0",
    "vulkan-1.0",
    // TODO: can't translate until javascriptcore-4.1 is fixed
    // "webkit2-4.1",
    // TODO: can't translate until javascriptcore-4.1 is fixed
    // "webkit2webextension-4.1",
    // TODO: can't translate until javascriptcore-6.0 is fixed
    // "webkit-6.0",
    // TODO: can't translate until javascriptcore-6.0 is fixed
    // "webkitwebprocessextension-6.0",
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
