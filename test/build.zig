const std = @import("std");
const gobject_build = @import("gobject");

const ModuleOptions = struct {
    test_abi: bool = true,
};

const module_options = std.ComptimeStringMap(ModuleOptions, .{
    .{
        "appstreamcompose-1.0", .{
            // TODO: have to define I_KNOW_THE_APPSTREAM_COMPOSE_API_IS_SUBJECT_TO_CHANGE
            .test_abi = false,
        },
    },
    .{
        "atspi-2.0", .{
            // TODO: incorrect translation of time_added field in Application
            .test_abi = false,
        },
    },
    .{
        "cairo-1.0", .{
            // TODO: the ABI tests don't work for manually created bindings
            .test_abi = false,
        },
    },
    .{
        "dex-1", .{
            // Header file libdex.h not found
            .test_abi = false,
        },
    },
    .{
        "gcr-3", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "gcr-4", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "gcrui-3", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "gdk-3.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gdkpixbuf-2.0", .{
            // GdkPixbufAnimation and GdkPixbufAnimationIter seemingly are final
            // without being marked as such in GIR
            .test_abi = false,
        },
    },
    .{
        "gio-2.0", .{
            // Something weird going on with GSettingsBackend being translated as opaque
            .test_abi = false,
        },
    },
    .{
        "glib-2.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gobject-2.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "graphene-1.0", .{
            // Uses non-portable conditional SIMD types; the GIR won't work unless it's generated on the same target
            .test_abi = false,
        },
    },
    .{
        "gsk-4.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gst-1.0", .{
            // GstMemoryCopyFunction: https://github.com/ziglang/zig/issues/12325
            .test_abi = false,
        },
    },
    .{
        "gstapp-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstaudio-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstbase-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstcheck-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstgl-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstglegl-1.0", .{
            // GstMemoryCopyFunction: https://github.com/ziglang/zig/issues/12325
            .test_abi = false,
        },
    },
    .{
        "gstinsertbin-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstpbutils-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstrtp-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gsttag-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstvideo-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gstvulkan-1.0", .{
            // Missing include vulkan/vulkan_core.h
            .test_abi = false,
        },
    },
    .{
        "gstvulkanwayland-1.0", .{
            // Missing include vulkan/vulkan_core.h
            .test_abi = false,
        },
    },
    .{
        "gtk-3.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "gtksource-4", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "handy-1", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "pango-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "pangocairo-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "pangofc-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "pangoft2-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "pangoot-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
});

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run binding tests");

    const GirProfile = enum { gnome44, gnome45 };
    const gir_profile = b.option(GirProfile, "gir-profile", "Predefined GIR profile for tests");
    const test_modules: []const []const u8 = b.option([]const []const u8, "modules", "Modules to test") orelse if (gir_profile) |profile| switch (profile) {
        .gnome44 => &.{
            "Adw-1",
            "AppStreamGlib-1.0",
            "Atk-1.0",
            "Atspi-2.0",
            "cairo-1.0",
            "DBus-1.0",
            // "DBusGLib-1.0", // Unable to find system library
            "fontconfig-2.0",
            "freetype2-2.0",
            "GCab-1.0",
            // "Gck-1", // Not enough type information available to translate
            // "Gck-2", // Not enough type information available to translate
            "Gcr-3",
            "Gcr-4",
            "GcrUi-3",
            "GDesktopEnums-3.0",
            "Gdk-3.0",
            "Gdk-4.0",
            "GdkPixbuf-2.0",
            "GdkPixdata-2.0",
            "GdkWayland-4.0",
            "GdkX11-3.0",
            "GdkX11-4.0",
            // "Gee-0.8", // Several GIR issues, including referencing undefined types
            "Geoclue-2.0",
            "Gio-2.0",
            "GIRepository-2.0",
            "GL-1.0",
            "GLib-2.0",
            "GModule-2.0",
            "GObject-2.0",
            "Graphene-1.0",
            "Gsk-4.0",
            // "Gst-1.0", // GIR incorrectly marks va_list as nullable
            "GstAllocators-1.0",
            "GstApp-1.0",
            "GstAudio-1.0",
            "GstBadAudio-1.0",
            "GstBase-1.0",
            "GstCheck-1.0",
            // "GstCodecs-1.0", // Unable to find system library
            "GstController-1.0",
            "GstGL-1.0",
            "GstGLEGL-1.0",
            "GstGLWayland-1.0",
            "GstGLX11-1.0",
            "GstInsertBin-1.0",
            "GstMpegts-1.0",
            "GstNet-1.0",
            "GstPbutils-1.0",
            "GstPlay-1.0",
            "GstPlayer-1.0",
            "GstRtp-1.0",
            "GstRtsp-1.0",
            "GstSdp-1.0",
            "GstTag-1.0",
            "GstTranscoder-1.0",
            "GstVideo-1.0",
            // "GstVulkan-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            // "GstVulkanWayland-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            // "GstVulkanXCB-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            "GstWebRTC-1.0",
            "Gtk-3.0",
            "Gtk-4.0",
            "GtkSource-4",
            "GtkSource-5",
            "GUdev-1.0",
            "Handy-1",
            "HarfBuzz-0.0",
            "IBus-1.0",
            "JavaScriptCore-4.1",
            "JavaScriptCore-6.0",
            "Json-1.0",
            "libxml2-2.0",
            "Manette-0.2",
            "Nice-0.1",
            "Notify-0.7",
            "Pango-1.0",
            "PangoCairo-1.0",
            "PangoFc-1.0",
            "PangoFT2-1.0",
            "PangoOT-1.0",
            "Polkit-1.0",
            "Rsvg-2.0",
            "Secret-1",
            "Soup-3.0",
            "Tracker-3.0",
            "Vulkan-1.0",
            // "WebKit2-4.1", // Not enough type information available to translate
            // "WebKit2WebExtension-4.1", // Not enough type information available to translate
            "WebKit-6.0",
            "WebKitWebProcessExtension-6.0",
            "win32-1.0",
            "xfixes-4.0",
            "xft-2.0",
            "xlib-2.0",
            "xrandr-1.3",
        },
        .gnome45 => &.{
            "Adw-1",
            "AppStream-1.0",
            "AppStreamCompose-1.0",
            "AppStreamGlib-1.0",
            "Atk-1.0",
            "Atspi-2.0",
            "Avahi-0.6",
            "AvahiCore-0.6",
            "cairo-1.0",
            "CudaGst-1.0",
            "DBus-1.0",
            // "DBusGLib-1.0", // Unable to find system library
            "Dex-1",
            "fontconfig-2.0",
            "freetype2-2.0",
            "GCab-1.0",
            // "Gck-1", // Not enough type information available to translate
            // "Gck-2", // Not enough type information available to translate
            "Gcr-3",
            "Gcr-4",
            "GcrUi-3",
            "GDesktopEnums-3.0",
            "Gdk-3.0",
            "Gdk-4.0",
            "GdkPixbuf-2.0",
            "GdkPixdata-2.0",
            "GdkWayland-4.0",
            "GdkX11-3.0",
            "GdkX11-4.0",
            // "Gee-0.8", // Several GIR issues, including referencing undefined types
            "Geoclue-2.0",
            "Gio-2.0",
            "GIRepository-2.0",
            "GL-1.0",
            "GLib-2.0",
            "GModule-2.0",
            "GObject-2.0",
            "Graphene-1.0",
            "Gsk-4.0",
            // "Gst-1.0", // GIR incorrectly marks va_list as nullable
            "GstAllocators-1.0",
            "GstApp-1.0",
            "GstAudio-1.0",
            "GstBadAudio-1.0",
            "GstBase-1.0",
            "GstCheck-1.0",
            // "GstCodecs-1.0", // Unable to find system library
            "GstController-1.0",
            "GstCuda-1.0",
            "GstGL-1.0",
            "GstGLEGL-1.0",
            "GstGLWayland-1.0",
            "GstGLX11-1.0",
            "GstInsertBin-1.0",
            "GstMpegts-1.0",
            "GstNet-1.0",
            "GstPbutils-1.0",
            "GstPlay-1.0",
            "GstPlayer-1.0",
            "GstRtp-1.0",
            "GstRtsp-1.0",
            "GstSdp-1.0",
            "GstTag-1.0",
            "GstTranscoder-1.0",
            "GstVa-1.0",
            "GstVideo-1.0",
            // "GstVulkan-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            // "GstVulkanWayland-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            // "GstVulkanXCB-1.0", // Vulkan GIR is incorrect; all records should have pointer="1"
            "GstWebRTC-1.0",
            "Gtk-3.0",
            "Gtk-4.0",
            "GtkSource-5",
            "GUdev-1.0",
            "Handy-1",
            "HarfBuzz-0.0",
            "IBus-1.0",
            "JavaScriptCore-4.1",
            "JavaScriptCore-6.0",
            "Json-1.0",
            "Libproxy-1.0",
            "libxml2-2.0",
            "Manette-0.2",
            "Nice-0.1",
            "Notify-0.7",
            "Pango-1.0",
            "PangoCairo-1.0",
            "PangoFc-1.0",
            "PangoFT2-1.0",
            "PangoOT-1.0",
            "Polkit-1.0",
            "Rsvg-2.0",
            "Secret-1",
            "Soup-3.0",
            "Tracker-3.0",
            "Vulkan-1.0",
            // "WebKit2-4.1", // Not enough type information available to translate
            // "WebKit2WebExtension-4.1", // Not enough type information available to translate
            "WebKit-6.0",
            "WebKitWebProcessExtension-6.0",
            "win32-1.0",
            "xfixes-4.0",
            "xft-2.0",
            "xlib-2.0",
            "Xmlb-2.0",
            "xrandr-1.3",
        },
    } else @panic("No modules or GIR profile defined to test");

    for (test_modules) |test_module| {
        const module = try std.ascii.allocLowerString(b.allocator, test_module);
        const options = module_options.get(module) orelse ModuleOptions{};
        const dash_index = std.mem.indexOfScalar(u8, module, '-').?;
        const local_name = module[0..dash_index];

        const tests = b.addTest(.{
            .root_source_file = .{ .path = b.fmt("{s}.zig", .{module}) },
            .target = target,
            .optimize = optimize,
        });
        tests.root_module.addImport(local_name, gobject.module(module));
        test_step.dependOn(&b.addRunArtifact(tests).step);

        if (options.test_abi) {
            const abi_tests = b.addTest(.{
                .root_source_file = .{ .path = b.pathJoin(&.{ "abi", b.fmt("{s}.abi.zig", .{module}) }) },
                .target = target,
                .optimize = optimize,
            });
            abi_tests.root_module.addImport(module, gobject.module(module));
            inline for (@typeInfo(gobject_build.libraries).Struct.decls) |lib_decl| {
                if (std.mem.eql(u8, lib_decl.name, module)) {
                    @field(gobject_build.libraries, lib_decl.name).linkTo(&abi_tests.root_module);
                }
            }
            test_step.dependOn(&b.addRunArtifact(abi_tests).step);
        }
    }
}
