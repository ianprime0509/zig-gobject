const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml = b.dependency("xml", .{}).module("xml");

    const exe = b.addExecutable(.{
        .name = "zig-gobject",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.root_module.addImport("xml", xml);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the binding generator");
    run_step.dependOn(&run_cmd.step);

    try addCodegenStep(b, exe);

    // Tests
    const test_step = b.step("test", "Run all tests");

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.linkLibC();
    exe_tests.root_module.addImport("xml", xml);

    const test_exe_step = b.step("test-exe", "Run tests for the binding generator");
    test_exe_step.dependOn(&b.addRunArtifact(exe_tests).step);
    test_step.dependOn(test_exe_step);
}

fn addCodegenStep(b: *std.Build, codegen_exe: *std.Build.Step.Compile) !void {
    const GirProfile = enum { gnome44, gnome45 };
    const gir_profile = b.option(GirProfile, "gir-profile", "Predefined GIR profile for codegen") orelse .gnome45;
    const codegen_modules: []const []const u8 = b.option([]const []const u8, "modules", "Modules to codegen") orelse switch (gir_profile) {
        .gnome44 => &.{
            "Adw-1",
            "AppStreamGlib-1.0",
            "Atk-1.0",
            "Atspi-2.0",
            "cairo-1.0",
            "DBus-1.0",
            "DBusGLib-1.0",
            "fontconfig-2.0",
            "freetype2-2.0",
            "GCab-1.0",
            "Gck-1",
            "Gck-2",
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
            "Gee-0.8",
            "Geoclue-2.0",
            "Gio-2.0",
            "GIRepository-2.0",
            "GL-1.0",
            "GLib-2.0",
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
            "GstCodecs-1.0",
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
            "GstVulkan-1.0",
            "GstVulkanWayland-1.0",
            "GstVulkanXCB-1.0",
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
            "libintl-0.0",
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
            "WebKit2-4.1",
            "WebKit2WebExtension-4.1",
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
            "DBusGLib-1.0",
            "Dex-1",
            "fontconfig-2.0",
            "freetype2-2.0",
            "GCab-1.0",
            "Gck-1",
            "Gck-2",
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
            "Gee-0.8",
            "Geoclue-2.0",
            "Gio-2.0",
            "GIRepository-2.0",
            "GL-1.0",
            "GLib-2.0",
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
            "GstCodecs-1.0",
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
            "GstVulkan-1.0",
            "GstVulkanWayland-1.0",
            "GstVulkanXCB-1.0",
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
            "libintl-0.0",
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
            "WebKit2-4.1",
            "WebKit2WebExtension-4.1",
            "WebKit-6.0",
            "WebKitWebProcessExtension-6.0",
            "win32-1.0",
            "xfixes-4.0",
            "xft-2.0",
            "xlib-2.0",
            "Xmlb-2.0",
            "xrandr-1.3",
        },
    };

    const binding_override_modules = std.ComptimeStringMap(void, .{
        .{"cairo-1.0"},
    });

    const gir_override_modules = std.ComptimeStringMap(void, .{
        .{"freetype2-2.0"},
        .{"libintl-0.0"},
    });

    const extension_modules = std.ComptimeStringMap(void, .{
        .{"glib-2.0"},
        .{"gtk-4.0"},
        .{"gobject-2.0"},
        .{"libintl-0.0"},
    });

    const codegen_cmd = b.addRunArtifact(codegen_exe);
    codegen_cmd.addArgs(&.{ "--gir-dir", try b.build_root.join(b.allocator, &.{"gir-overrides"}) });
    const gir_files_path = b.option([]const u8, "gir-files-path", "Path to GIR files") orelse "/usr/share/gir-1.0";
    codegen_cmd.addArgs(&.{ "--gir-dir", gir_files_path });
    codegen_cmd.addArgs(&.{ "--bindings-dir", try b.build_root.join(b.allocator, &.{"binding-overrides"}) });
    codegen_cmd.addArgs(&.{ "--extensions-dir", try b.build_root.join(b.allocator, &.{"extensions"}) });
    codegen_cmd.addArg("--output-dir");
    const bindings_dir = codegen_cmd.addOutputFileArg("bindings");
    codegen_cmd.addArgs(&.{ "--abi-test-output-dir", try b.build_root.join(b.allocator, &.{ "test", "abi" }) });

    var file_deps = std.ArrayList([]const u8).init(b.allocator);
    for (codegen_modules) |module| {
        codegen_cmd.addArg(module);
        const file_name = b.fmt("{s}.gir", .{module});
        if (gir_override_modules.has(module)) {
            try file_deps.append(try b.build_root.join(b.allocator, &.{ "gir-overrides", file_name }));
        } else {
            try file_deps.append(b.pathJoin(&.{ gir_files_path, file_name }));
        }
        if (binding_override_modules.has(module)) {
            const binding_file_name = b.fmt("{s}.zig", .{module});
            try file_deps.append(try b.build_root.join(b.allocator, &.{ "binding-overrides", binding_file_name }));
        }
        if (extension_modules.has(module)) {
            const extension_file_name = b.fmt("{s}.ext.zig", .{module});
            try file_deps.append(try b.build_root.join(b.allocator, &.{ "extensions", extension_file_name }));
        }
    }
    codegen_cmd.extra_file_dependencies = file_deps.items;
    codegen_cmd.expectExitCode(0);

    const install_bindings = b.addInstallDirectory(.{
        .source_dir = bindings_dir,
        .install_dir = .prefix,
        .install_subdir = "bindings",
    });

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&install_bindings.step);
}
