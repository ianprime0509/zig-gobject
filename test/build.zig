const std = @import("std");
const gobject_build = @import("gobject");

const ModuleOptions = struct {
    test_abi: bool = true,
};

const module_options = std.StaticStringMap(ModuleOptions).initComptime(.{
    .{
        "AppStreamCompose-1.0", .{
            // TODO: have to define I_KNOW_THE_APPSTREAM_COMPOSE_API_IS_SUBJECT_TO_CHANGE
            .test_abi = false,
        },
    },
    .{
        "Atspi-2.0", .{
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
        "Dex-1", .{
            // Header file libdex.h not found
            .test_abi = false,
        },
    },
    .{
        "Gcr-3", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "Gcr-4", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "GcrUi-3", .{
            // C includes yield error "This API has not yet reached stability."
            .test_abi = false,
        },
    },
    .{
        "Gdk-3.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GdkPixbuf-2.0", .{
            // GdkPixbufAnimation and GdkPixbufAnimationIter seemingly are final
            // without being marked as such in GIR
            .test_abi = false,
        },
    },
    .{
        "Gio-2.0", .{
            // Something weird going on with GSettingsBackend being translated as opaque
            .test_abi = false,
        },
    },
    .{
        "GLib-2.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GObject-2.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "Graphene-1.0", .{
            // Uses non-portable conditional SIMD types; the GIR won't work unless it's generated on the same target
            .test_abi = false,
        },
    },
    .{
        "Gsk-4.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "Gst-1.0", .{
            // GstMemoryCopyFunction: https://github.com/ziglang/zig/issues/12325
            .test_abi = false,
        },
    },
    .{
        "GstApp-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstAudio-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstBase-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstCheck-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstGL-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstGLEGL-1.0", .{
            // GstMemoryCopyFunction: https://github.com/ziglang/zig/issues/12325
            .test_abi = false,
        },
    },
    .{
        "GstInsertBin-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstMse-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstPbutils-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstRtp-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstTag-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstVideo-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "GstVulkan-1.0", .{
            // Missing include vulkan/vulkan_core.h
            .test_abi = false,
        },
    },
    .{
        "GstVulkanWayland-1.0", .{
            // Missing include vulkan/vulkan_core.h
            .test_abi = false,
        },
    },
    .{
        "Gtk-3.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "Handy-1", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "Pango-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "PangoCairo-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "PangoFc-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "PangoFT2-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
    .{
        "PangoOT-1.0", .{
            // Needs more comprehensive checks to skip indirect bit field references
            .test_abi = false,
        },
    },
});

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run binding tests");

    const GirProfile = enum { gnome46, gnome47 };
    const gir_profile = b.option(GirProfile, "gir-profile", "Predefined GIR profile for tests");
    const test_modules: []const []const u8 = b.option([]const []const u8, "modules", "Modules to test") orelse if (gir_profile) |profile| switch (profile) {
        .gnome46 => &.{
            "Adw-1",
            "AppStream-1.0",
            "AppStreamCompose-1.0",
            "AppStreamGlib-1.0",
            "Atk-1.0",
            "Atspi-2.0",
            "cairo-1.0",
            "CudaGst-1.0",
            "DBus-1.0",
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
            "GioUnix-2.0",
            "GIRepository-2.0",
            "GIRepository-3.0",
            "GL-1.0",
            "GLib-2.0",
            "GLibUnix-2.0",
            "GModule-2.0",
            "GObject-2.0",
            "Graphene-1.0",
            "Gsk-4.0",
            "Gst-1.0",
            "GstAllocators-1.0",
            "GstApp-1.0",
            "GstAudio-1.0",
            "GstBadAudio-1.0",
            "GstBase-1.0",
            "GstCheck-1.0",
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
        .gnome47 => &.{
            "Adw-1",
            "AppStream-1.0",
            "AppStreamCompose-1.0",
            "Atk-1.0",
            "Atspi-2.0",
            "cairo-1.0",
            "CudaGst-1.0",
            "DBus-1.0",
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
            "GioUnix-2.0",
            "GIRepository-2.0",
            "GIRepository-3.0",
            "GL-1.0",
            "GLib-2.0",
            "GLibUnix-2.0",
            "GModule-2.0",
            "GObject-2.0",
            "Graphene-1.0",
            "Gsk-4.0",
            "Gst-1.0",
            "GstAllocators-1.0",
            "GstAnalytics-1.0",
            "GstApp-1.0",
            "GstAudio-1.0",
            "GstBadAudio-1.0",
            "GstBase-1.0",
            "GstCheck-1.0",
            "GstController-1.0",
            "GstCuda-1.0",
            // "GstDxva-1.0", // Not usable on Linux
            "GstGL-1.0",
            "GstGLEGL-1.0",
            "GstGLWayland-1.0",
            "GstGLX11-1.0",
            "GstInsertBin-1.0",
            "GstMpegts-1.0",
            "GstMse-1.0",
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
            "Tsparql-3.0",
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
    } else &.{};

    for (test_modules) |test_module| {
        const module_name_end = std.mem.indexOfScalar(u8, test_module, '-') orelse @panic("Invalid module name");
        const module_name = test_module[0..module_name_end];
        const module_major_version_end = std.mem.indexOfScalarPos(u8, test_module, module_name_end, '.') orelse test_module.len;
        const module_major_version = test_module[module_name_end + 1 .. module_major_version_end];
        const module = b.fmt("{s}{s}", .{ module_name, module_major_version });
        _ = std.ascii.lowerString(module, module);

        const options = module_options.get(test_module) orelse ModuleOptions{};

        const import_name = std.ascii.allocLowerString(b.allocator, module_name) catch @panic("OOM");
        const tests = b.addTest(.{
            .root_source_file = b.path(b.fmt("{s}.zig", .{module})),
            .target = target,
            .optimize = optimize,
        });
        tests.root_module.addImport(import_name, gobject.module(module));
        test_step.dependOn(&b.addRunArtifact(tests).step);

        if (options.test_abi) {
            const abi_tests = b.addTest(.{
                .root_source_file = b.path(b.pathJoin(&.{ "abi", b.fmt("{s}.abi.zig", .{module}) })),
                .target = target,
                .optimize = optimize,
            });
            abi_tests.root_module.addImport(module, gobject.module(module));
            inline for (comptime std.meta.declarations(gobject_build.libraries)) |lib_decl| {
                if (std.mem.eql(u8, lib_decl.name, module)) {
                    @field(gobject_build.libraries, lib_decl.name).linkTo(&abi_tests.root_module);
                }
            }
            test_step.dependOn(&b.addRunArtifact(abi_tests).step);
        }
    }
}
