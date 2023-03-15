const std = @import("std");
const libxml2 = @import("lib/zig-libxml2/libxml2.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libxml2_lib = try libxml2.create(b, target, optimize, .{
        .iconv = false,
        .lzma = false,
        .sax1 = true,
        .zlib = false,
    });

    const exe = b.addExecutable(.{
        .name = "zig-gobject",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    libxml2_lib.link(exe);
    exe.install();

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
    libxml2_lib.link(exe_tests);

    const test_exe_step = b.step("test-exe", "Run tests for the binding generator");
    test_exe_step.dependOn(&exe_tests.step);
    test_step.dependOn(test_exe_step);

    const test_bindings_cmd = b.addSystemCommand(&.{ b.zig_exe, "build", "test" });
    test_bindings_cmd.cwd = try b.build_root.join(b.allocator, &.{"test"});
    test_bindings_cmd.step.dependOn(codegen_step);

    const test_bindings_step = b.step("test-bindings", "Run binding tests");
    test_bindings_step.dependOn(&test_bindings_cmd.step);
    test_step.dependOn(test_bindings_step);

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
        "Atk-1.0.gir",
        "cairo-1.0.gir",
        "fontconfig-2.0.gir",
        "freetype2-2.0.gir",
        "Gdk-3.0.gir",
        "Gdk-4.0.gir",
        "GdkPixbuf-2.0.gir",
        "GdkPixdata-2.0.gir",
        "GdkWayland-4.0.gir",
        "GdkWin32-4.0.gir",
        "GdkX11-3.0.gir",
        "GdkX11-4.0.gir",
        "Gio-2.0.gir",
        "GL-1.0.gir",
        "GLib-2.0.gir",
        "GModule-2.0.gir",
        "GObject-2.0.gir",
        "Graphene-1.0.gir",
        "Gsk-4.0.gir",
        "Gtk-3.0.gir",
        "Gtk-4.0.gir",
        "HarfBuzz-0.0.gir",
        "libxml2-2.0.gir",
        "Pango-1.0.gir",
        "PangoCairo-1.0.gir",
        "PangoFc-1.0.gir",
        "PangoFT2-1.0.gir",
        "PangoOT-1.0.gir",
        "PangoXft-1.0.gir",
        "Vulkan-1.0.gir",
        "win32-1.0.gir",
        "xfixes-4.0.gir",
        "xft-2.0.gir",
        "xlib-2.0.gir",
        "xrandr-1.3.gir",
    };

    const extras = [_][]const u8{
        "cairo-1.0.gir.extras",
        "GLib-2.0.gir.extras",
        "GObject-2.0.gir.extras",
    };

    const codegen_cmd = b.addRunArtifact(codegen_exe);
    var repo_names = std.ArrayList([]const u8).init(b.allocator);
    var file_deps = std.ArrayList([]const u8).init(b.allocator);
    for (gir) |file| {
        try repo_names.append(file[0 .. file.len - ".gir".len]);
        try file_deps.append(try b.build_root.join(b.allocator, &.{ "lib", "gir-files", file }));
    }
    for (extras) |file| {
        try file_deps.append(try b.build_root.join(b.allocator, &.{ "gir-extras", file }));
    }
    codegen_cmd.extra_file_dependencies = file_deps.items;
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{ "lib", "gir-files" }));
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{"gir-extras"}));
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{"bindings"}));
    codegen_cmd.addArgs(repo_names.items);

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&codegen_cmd.step);
    return codegen_step;
}
