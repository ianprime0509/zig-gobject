const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn build(b: *std.Build) void {
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

    const GirProfile = enum { gnome45 };
    const gir_profile = b.option(GirProfile, "gir-profile", "Predefined GIR profile for codegen");
    const codegen_modules: []const []const u8 = b.option([]const []const u8, "modules", "Modules to codegen") orelse if (gir_profile) |profile| switch (profile) {
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
    } else &.{};

    const gir_files_path = b.option([]const u8, "gir-files-path", "Path to GIR files") orelse "/usr/share/gir-1.0";

    const codegen_cmd = b.addRunArtifact(exe);

    // GIR fixes are handled by prepending a directory containing all the fixed
    // GIRs to the search path. Fixed GIRs are produced from their originals
    // using XSLT (deemed the most straightforward and complete way to transform
    // XML semantically).
    const gir_fixes: []const []const u8 = b.option([]const []const u8, "gir-fixes", "GIR fixes to apply") orelse if (gir_profile) |profile| switch (profile) {
        .gnome45 => &.{
            fix(b, "AppStream-1.0", "common"),
            fix(b, "freetype2-2.0", "common"),
            fix(b, "GObject-2.0", "gnome45"),
        },
    } else &.{};
    if (gir_fixes.len > 0) gir_fixes: {
        const libxml2 = b.lazyDependency("libxml2", .{
            .target = target,
            .optimize = optimize,
            .xslt = true,
        }) orelse break :gir_fixes;
        const xsltproc = libxml2.artifact("xsltproc");
        const fixed_files = b.addWriteFiles();

        for (gir_fixes) |gir_fix| {
            const sep_pos = std.mem.indexOfScalar(u8, gir_fix, '=') orelse @panic("Invalid GIR fix provided (format: module=xslt-path)");
            const target_gir = b.fmt("{s}.gir", .{gir_fix[0..sep_pos]});
            const source_gir_path = b.pathJoin(&.{ gir_files_path, target_gir });
            const xslt_path = gir_fix[sep_pos + 1 ..];

            const run_xsltproc = b.addRunArtifact(xsltproc);
            run_xsltproc.addArg("-o");
            const output_gir = run_xsltproc.addOutputFileArg("gir-fix");
            run_xsltproc.addArg(xslt_path);
            run_xsltproc.addArg(source_gir_path);
            run_xsltproc.extra_file_dependencies = b.dupeStrings(&.{ xslt_path, source_gir_path });
            run_xsltproc.expectExitCode(0);

            _ = fixed_files.addCopyFile(output_gir, target_gir);
        }

        codegen_cmd.addArg("--gir-dir");
        codegen_cmd.addDirectoryArg(fixed_files.getDirectory());
    }

    codegen_cmd.addArgs(&.{ "--gir-dir", gir_files_path });
    codegen_cmd.addArgs(&.{ "--bindings-dir", b.pathFromRoot("binding-overrides") });
    codegen_cmd.addArgs(&.{ "--extensions-dir", b.pathFromRoot("extensions") });
    codegen_cmd.addArg("--output-dir");
    const bindings_dir = codegen_cmd.addOutputFileArg("bindings");
    codegen_cmd.addArgs(&.{ "--abi-test-output-dir", b.pathFromRoot("test/abi") });
    codegen_cmd.addArg("--dependency-file");
    _ = codegen_cmd.addDepFileOutputArg("codegen-deps");
    codegen_cmd.addArgs(codegen_modules);
    // This is needed to tell Zig that the command run can be cached despite
    // having output files.
    codegen_cmd.expectExitCode(0);

    const install_bindings = b.addInstallDirectory(.{
        .source_dir = bindings_dir,
        .install_dir = .prefix,
        .install_subdir = "bindings",
    });

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&install_bindings.step);
}

fn fix(b: *std.Build, module: []const u8, category: []const u8) []const u8 {
    const path = b.pathFromRoot(b.fmt("gir-fixes/{s}/{s}.xslt", .{ category, module }));
    return b.fmt("{s}={s}", .{ module, path });
}
