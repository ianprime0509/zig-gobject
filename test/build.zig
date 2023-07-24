const std = @import("std");
const zig_gobject = @import("lib/zig-gobject/build.zig");

const modules = [_][]const u8{
    "adw-1",
    "appstreamglib-1.0",
    "atk-1.0",
    "atspi-2.0",
    "cairo-1.0",
    "dbus-1.0",
    "dbusglib-1.0",
    "fontconfig-2.0",
    "freetype2-2.0",
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
    // TODO: the GIR has many issues, including referencing completely undefined
    // types (HazardPointerNode) and types with the wrong name (FutureMapFunc).
    // It seems to be generated from Vala rather than C, so maybe that's why.
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
    // TODO: va_list erroneously marked as nullable
    //"gst-1.0",
    "gstallocators-1.0",
    "gstapp-1.0",
    "gstaudio-1.0",
    "gstbadaudio-1.0",
    "gstbase-1.0",
    "gstcheck-1.0",
    // TODO: "not enough type information available"
    // "gstcodecs-1.0",
    "gstcontroller-1.0",
    "gstgl-1.0",
    "gstglegl-1.0",
    "gstglwayland-1.0",
    "gstglx11-1.0",
    "gstinsertbin-1.0",
    "gstmpegts-1.0",
    "gstnet-1.0",
    "gstpbutils-1.0",
    "gstplay-1.0",
    "gstplayer-1.0",
    "gstrtp-1.0",
    "gstrtsp-1.0",
    "gstsdp-1.0",
    "gsttag-1.0",
    "gsttranscoder-1.0",
    "gstvideo-1.0",
    "gstvulkan-1.0",
    "gstvulkanwayland-1.0",
    // TODO: can't find the package to install to link this
    // "gstvulkanxcb-1.0",
    "gstwebrtc-1.0",
    "gtk-3.0",
    "gtk-4.0",
    "gtksource-4",
    "gtksource-5",
    "gudev-1.0",
    "handy-1",
    "harfbuzz-0.0",
    "ibus-1.0",
    "javascriptcore-4.1",
    "javascriptcore-6.0",
    "json-1.0",
    "libintl-0.0",
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
    // TODO: "not enough type information available"
    // "webkit2-4.1",
    // TODO: "not enough type information available"
    // "webkit2webextension-4.1",
    "webkit-6.0",
    "webkitwebprocessextension-6.0",
    "win32-1.0",
    "xfixes-4.0",
    "xft-2.0",
    "xlib-2.0",
    "xrandr-1.3",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run binding tests");

    for (modules) |module| {
        const dash_index = std.mem.indexOfScalar(u8, module, '-').?;
        const local_name = module[0..dash_index];
        const tests = b.addTest(.{
            .root_source_file = .{ .path = b.fmt("{s}.zig", .{module}) },
            .target = target,
            .optimize = optimize,
        });
        tests.addModule(local_name, zig_gobject.addBindingModule(b, tests, module));
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
