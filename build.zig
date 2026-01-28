const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml = b.dependency("xml", .{}).module("xml");

    const codegen_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "xml", .module = xml },
        },
    });

    const codegen_exe = b.addExecutable(.{
        .name = "translate-gir",
        .root_module = codegen_mod,
    });
    b.installArtifact(codegen_exe);

    // Tests
    const test_step = b.step("test", "Run all tests");

    const codegen_test = b.addTest(.{ .root_module = codegen_mod });

    const test_exe_step = b.step("test-exe", "Run tests for the binding generator");
    test_exe_step.dependOn(&b.addRunArtifact(codegen_test).step);
    test_step.dependOn(test_exe_step);

    const GirProfile = enum { gnome48, gnome49 };
    const gir_profile = b.option(GirProfile, "gir-profile", "Predefined GIR profile for codegen");
    const codegen_modules: []const []const u8 = b.option([]const []const u8, "modules", "Modules to codegen") orelse if (gir_profile) |profile| switch (profile) {
        .gnome48 => &.{
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
            // "GstVulkan-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
            // "GstVulkanWayland-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
            // "GstVulkanXCB-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
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
            // "Vulkan-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
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
        .gnome49 => &.{
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
            "GioUnix-2.0",
            "GIRepository-2.0",
            "GIRepository-3.0",
            "GL-1.0",
            "GLib-2.0",
            "GLibUnix-2.0",
            "Gly-2",
            "GlyGtk4-2",
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
            // "GstVulkan-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
            // "GstVulkanWayland-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
            // "GstVulkanXCB-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
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
            // "Vulkan-1.0", // https://github.com/ianprime0509/zig-gobject/issues/89
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
    } else &.{};

    const gir_files_paths: []const []const u8 = b.option([]const []const u8, "gir-files-path", "Path to GIR files") orelse &.{"/usr/share/gir-1.0"};

    const codegen_exe_run = b.addRunArtifact(codegen_exe);

    for (gir_files_paths) |path| {
        codegen_exe_run.addPrefixedDirectoryArg("--gir-dir=", .{ .cwd_relative = path });
    }
    codegen_exe_run.addPrefixedDirectoryArg("--gir-fixes-dir=", b.path("gir-fixes"));
    codegen_exe_run.addPrefixedDirectoryArg("--bindings-dir=", b.path("binding-overrides"));
    codegen_exe_run.addPrefixedDirectoryArg("--extensions-dir=", b.path("extensions"));
    const bindings_dir = codegen_exe_run.addPrefixedOutputDirectoryArg("--output-dir=", "bindings");
    codegen_exe_run.addPrefixedDirectoryArg("--abi-test-output-dir=", b.path("test/abi"));
    _ = codegen_exe_run.addPrefixedDepFileOutputArg("--dependency-file=", "codegen-deps");
    codegen_exe_run.addArgs(codegen_modules);
    // This is needed to tell Zig that the command run can be cached despite
    // having output files.
    codegen_exe_run.expectExitCode(0);

    const install_bindings = b.addInstallDirectory(.{
        .source_dir = bindings_dir,
        .install_dir = .prefix,
        .install_subdir = "bindings",
    });

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&install_bindings.step);
}
