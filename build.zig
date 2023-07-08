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
    exe.addModule("xml", xml);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the binding generator");
    run_step.dependOn(&run_cmd.step);

    const codegen_step = try addCodegenStep(b, exe);

    // Tests
    const test_step = b.step("test", "Run all tests");

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.linkLibC();
    exe_tests.addModule("xml", xml);

    const test_exe_step = b.step("test-exe", "Run tests for the binding generator");
    test_exe_step.dependOn(&b.addRunArtifact(exe_tests).step);
    test_step.dependOn(test_exe_step);

    const skip_binding_tests = b.option(bool, "skip-binding-tests", "Skip tests for generated bindings") orelse false;
    if (!skip_binding_tests) {
        const test_bindings_cmd = b.addSystemCommand(&.{ b.zig_exe, "build", "test" });
        test_bindings_cmd.cwd = try b.build_root.join(b.allocator, &.{"test"});
        test_bindings_cmd.step.dependOn(codegen_step);

        const test_bindings_step = b.step("test-bindings", "Run binding tests");
        test_bindings_step.dependOn(&test_bindings_cmd.step);
        test_step.dependOn(test_bindings_step);
    }

    // Examples
    const run_example_cmd = b.addSystemCommand(&.{ b.zig_exe, "build", "run" });
    run_example_cmd.cwd = try b.build_root.join(b.allocator, &.{"examples"});
    run_example_cmd.step.dependOn(codegen_step);

    const run_example_step = b.step("run-example", "Run the example launcher");
    run_example_step.dependOn(&run_example_cmd.step);
}

fn addCodegenStep(b: *std.Build, codegen_exe: *std.Build.CompileStep) !*std.Build.Step {
    const gir = [_][]const u8{
        "Adw-1.gir",
        "AppStreamGlib-1.0.gir",
        "Atk-1.0.gir",
        "Atspi-2.0.gir",
        "cairo-1.0.gir",
        "DBus-1.0.gir",
        "DBusGLib-1.0.gir",
        "fontconfig-2.0.gir",
        "freetype2-2.0.gir",
        "GCab-1.0.gir",
        "Gck-1.gir",
        "Gck-2.gir",
        "Gcr-3.gir",
        "Gcr-4.gir",
        "GcrUi-3.gir",
        "GDesktopEnums-3.0.gir",
        "Gdk-3.0.gir",
        "Gdk-4.0.gir",
        "GdkPixbuf-2.0.gir",
        "GdkPixdata-2.0.gir",
        "GdkWayland-4.0.gir",
        "GdkX11-3.0.gir",
        "GdkX11-4.0.gir",
        "Gee-0.8.gir",
        "Geoclue-2.0.gir",
        "Gio-2.0.gir",
        "GIRepository-2.0.gir",
        "GL-1.0.gir",
        "GLib-2.0.gir",
        "GModule-2.0.gir",
        "GObject-2.0.gir",
        "Graphene-1.0.gir",
        "Gsk-4.0.gir",
        "Gst-1.0.gir",
        "GstAllocators-1.0.gir",
        "GstApp-1.0.gir",
        "GstAudio-1.0.gir",
        "GstBadAudio-1.0.gir",
        "GstBase-1.0.gir",
        "GstCheck-1.0.gir",
        "GstCodecs-1.0.gir",
        "GstController-1.0.gir",
        "GstGL-1.0.gir",
        "GstGLEGL-1.0.gir",
        "GstGLWayland-1.0.gir",
        "GstGLX11-1.0.gir",
        "GstInsertBin-1.0.gir",
        "GstMpegts-1.0.gir",
        "GstNet-1.0.gir",
        "GstPbutils-1.0.gir",
        "GstPlay-1.0.gir",
        "GstPlayer-1.0.gir",
        "GstRtp-1.0.gir",
        "GstRtsp-1.0.gir",
        "GstSdp-1.0.gir",
        "GstTag-1.0.gir",
        "GstTranscoder-1.0.gir",
        "GstVideo-1.0.gir",
        "GstVulkan-1.0.gir",
        "GstVulkanWayland-1.0.gir",
        "GstVulkanXCB-1.0.gir",
        "GstWebRTC-1.0.gir",
        "Gtk-3.0.gir",
        "Gtk-4.0.gir",
        "GtkSource-4.gir",
        "GtkSource-5.gir",
        "GUdev-1.0.gir",
        "Handy-1.gir",
        "HarfBuzz-0.0.gir",
        "IBus-1.0.gir",
        "JavaScriptCore-4.1.gir",
        "JavaScriptCore-6.0.gir",
        "Json-1.0.gir",
        "libxml2-2.0.gir",
        "Manette-0.2.gir",
        "Nice-0.1.gir",
        "Notify-0.7.gir",
        "Pango-1.0.gir",
        "PangoCairo-1.0.gir",
        "PangoFc-1.0.gir",
        "PangoFT2-1.0.gir",
        "PangoOT-1.0.gir",
        "Polkit-1.0.gir",
        "Rsvg-2.0.gir",
        "Secret-1.gir",
        "Soup-3.0.gir",
        "Tracker-3.0.gir",
        "Vulkan-1.0.gir",
        "WebKit2-4.1.gir",
        "WebKit2WebExtension-4.1.gir",
        "WebKit-6.0.gir",
        "WebKitWebProcessExtension-6.0.gir",
        "win32-1.0.gir",
        "xfixes-4.0.gir",
        "xft-2.0.gir",
        "xlib-2.0.gir",
        "xrandr-1.3.gir",
    };

    const gir_overrides = [_][]const u8{
        "freetype2-2.0.gir",
    };

    const extras = [_][]const u8{
        "cairo-1.0.extras.zig",
        "glib-2.0.extras.zig",
        "gtk-4.0.extras.zig",
        "gobject-2.0.extras.zig",
    };

    const codegen_cmd = b.addRunArtifact(codegen_exe);
    var repo_names = std.ArrayList([]const u8).init(b.allocator);
    var file_deps = std.ArrayList([]const u8).init(b.allocator);
    for (gir) |file| {
        try repo_names.append(file[0 .. file.len - ".gir".len]);
        try file_deps.append(try b.build_root.join(b.allocator, &.{ "lib", "gir-files", file }));
    }
    for (gir_overrides) |file| {
        try file_deps.append(try b.build_root.join(b.allocator, &.{ "gir-overrides", file }));
    }
    for (extras) |file| {
        try file_deps.append(try b.build_root.join(b.allocator, &.{ "extras", file }));
    }
    codegen_cmd.extra_file_dependencies = file_deps.items;

    var search_path = ArrayListUnmanaged(u8){};
    try search_path.appendSlice(b.allocator, try b.build_root.join(b.allocator, &.{"gir-overrides"}));
    try search_path.append(b.allocator, std.fs.path.delimiter);
    try search_path.appendSlice(b.allocator, try b.build_root.join(b.allocator, &.{ "lib", "gir-files" }));
    codegen_cmd.addArg(search_path.items);
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{"extras"}));
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{"bindings"}));
    codegen_cmd.addArgs(repo_names.items);

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&codegen_cmd.step);
    return codegen_step;
}
