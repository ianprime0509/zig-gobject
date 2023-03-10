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
    // See https://github.com/ziglang/zig/issues/14666
    run_cmd.condition = .always;
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.linkLibC();
    libxml2_lib.link(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    var gir_dir_path = try b.build_root.join(b.allocator, &.{ "lib", "gir-files" });
    var gir_files = blk: {
        var files = std.ArrayList([]u8).init(b.allocator);
        var gir_dir = try std.fs.cwd().openIterableDir(gir_dir_path, .{});
        defer gir_dir.close();
        var gir_dir_iter = gir_dir.iterate();
        while (try gir_dir_iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".gir")) {
                try files.append(try b.allocator.dupe(u8, entry.name[0 .. entry.name.len - ".gir".len]));
            }
        }
        break :blk files;
    };

    var extras_dir_path = try b.build_root.join(b.allocator, &.{"gir-extras"});
    var extras_paths = blk: {
        var paths = std.ArrayList([]u8).init(b.allocator);
        var extras_dir = try std.fs.cwd().openIterableDir(extras_dir_path, .{});
        defer extras_dir.close();
        var extras_dir_iter = extras_dir.iterate();
        while (try extras_dir_iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".gir.extras")) {
                try paths.append(try b.allocator.dupe(u8, entry.name));
            }
        }
        break :blk paths;
    };

    const codegen_cmd = b.addRunArtifact(exe);
    var gir_dependencies = blk: {
        var deps = std.ArrayList([]u8).init(b.allocator);
        for (gir_files.items) |file| {
            var file_name = try std.fmt.allocPrint(b.allocator, "{s}.gir", .{file});
            defer b.allocator.free(file_name);
            try deps.append(try b.build_root.join(b.allocator, &.{ "lib", "gir-files", file_name }));
        }
        for (extras_paths.items) |path| {
            try deps.append(try b.build_root.join(b.allocator, &.{ "gir-extras", path }));
        }
        break :blk deps;
    };
    codegen_cmd.extra_file_dependencies = gir_dependencies.items;
    codegen_cmd.addArg(gir_dir_path);
    codegen_cmd.addArg(extras_dir_path);
    codegen_cmd.addArg(try b.build_root.join(b.allocator, &.{ "src", "gir-out" }));
    codegen_cmd.addArgs(gir_files.items);

    const codegen_step = b.step("codegen", "Generate all bindings");
    codegen_step.dependOn(&codegen_cmd.step);

    const binding_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/binding_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    binding_tests.linkLibC();
    binding_tests.linkSystemLibrary("gtk4");
    test_step.dependOn(&binding_tests.step);

    const example_exe = b.addExecutable(.{
        .name = "zig-gobject-example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    example_exe.linkLibC();
    example_exe.linkSystemLibrary("gtk4");
    example_exe.step.dependOn(&codegen_cmd.step);

    const example_build_step = b.step("example-build", "Build the example");
    example_build_step.dependOn(&example_exe.step);

    const example_run_cmd = b.addRunArtifact(example_exe);
    example_run_cmd.condition = .always;
    example_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        example_run_cmd.addArgs(args);
    }

    const example_run_step = b.step("example-run", "Run the example");
    example_run_step.dependOn(&example_run_cmd.step);
}
