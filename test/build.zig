const std = @import("std");
const gobject_build = @import("gobject");

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
    // TODO: Vulkan-1.0.gir is incorrect; all records should have pointer="1"
    // "gstvulkan-1.0",
    // TODO: Vulkan-1.0.gir is incorrect; all records should have pointer="1"
    // "gstvulkanwayland-1.0",
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

const ModuleOptions = struct {
    test_abi: bool = true,
};

const module_options = std.ComptimeStringMap(ModuleOptions, .{
    .{
        "atspi-2.0", .{
            // TODO: incorrect translation of time_added field in Application
            .test_abi = false,
        },
    },
    .{
        "cairo-1.0", .{
            // TODO: the GIR for image_surface_create is incorrect. Issue #18 will fix this.
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

    const test_modules = b.option([]const []const u8, "modules", "Modules to test") orelse &modules;
    for (test_modules) |module| {
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
