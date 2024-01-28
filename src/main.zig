const std = @import("std");
const gir = @import("gir.zig");
const translate = @import("translate.zig");
const log = std.log;
const mem = std.mem;

const usage =
    \\Usage: zig-gobject [options] [root...]
    \\
    \\Generates bindings for the given root namespaces and their dependencies.
    \\
    \\Options:
    \\  -h, --help                          Show this help
    \\      --bindings-dir DIR              Add a directory to the bindings search path (for manual bindings)
    \\      --extensions-dir DIR            Add a directory to the extensions search path
    \\      --gir-dir DIR                   Add a directory to the GIR search path
    \\      --output-dir DIR                Set the output directory
    \\      --abi-test-output-dir DIR       Set the output directory for ABI tests
;

pub fn main() u8 {
    mainInner() catch |e| switch (e) {
        error.InvalidArguments => return 1,
        else => {
            const error_return_trace = @errorReturnTrace();
            log.err("Unexpected error: {}", .{e});
            if (error_return_trace) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        },
    };
    return 0;
}

fn mainInner() !void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var gir_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer gir_path.deinit();
    defer for (gir_path.items) |*dir| dir.close();
    var bindings_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer bindings_path.deinit();
    defer for (bindings_path.items) |*dir| dir.close();
    var extensions_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer extensions_path.deinit();
    defer for (extensions_path.items) |*dir| dir.close();
    var output_dir: ?std.fs.Dir = null;
    defer if (output_dir) |*dir| dir.close();
    var abi_test_output_dir: ?std.fs.Dir = null;
    defer if (abi_test_output_dir) |*dir| dir.close();
    var roots = std.ArrayList(gir.Include).init(allocator);
    defer roots.deinit();
    defer for (roots.items) |root| {
        allocator.free(root.name);
        allocator.free(root.version);
    };

    var processing_options = true;
    while (args.next()) |arg| {
        if (processing_options and mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                try std.io.getStdOut().writeAll(usage);
                return;
            } else if (mem.eql(u8, arg, "--bindings-dir")) {
                const bindings_dir_path = args.next() orelse {
                    log.err("Expected directory after --bindings-dir", .{});
                    return error.InvalidArguments;
                };
                try bindings_path.append(try std.fs.cwd().openDir(bindings_dir_path, .{}));
            } else if (mem.eql(u8, arg, "--extensions-dir")) {
                const extensions_dir_path = args.next() orelse {
                    log.err("Expected directory after --extensions-dir", .{});
                    return error.InvalidArguments;
                };
                try extensions_path.append(try std.fs.cwd().openDir(extensions_dir_path, .{}));
            } else if (mem.eql(u8, arg, "--gir-dir")) {
                const gir_dir_path = args.next() orelse {
                    log.err("Expected directory after --gir-dir", .{});
                    return error.InvalidArguments;
                };
                try gir_path.append(try std.fs.cwd().openDir(gir_dir_path, .{}));
            } else if (mem.eql(u8, arg, "--output-dir")) {
                const output_dir_path = args.next() orelse {
                    log.err("Expected directory after --output-dir", .{});
                    return error.InvalidArguments;
                };
                if (output_dir) |*dir| dir.close();
                output_dir = try std.fs.cwd().makeOpenPath(output_dir_path, .{});
            } else if (mem.eql(u8, arg, "--abi-test-output-dir")) {
                const abi_test_output_dir_path = args.next() orelse {
                    log.err("Expected directory after --abi-test-output-dir", .{});
                    return error.InvalidArguments;
                };
                if (abi_test_output_dir) |*dir| dir.close();
                abi_test_output_dir = try std.fs.cwd().makeOpenPath(abi_test_output_dir_path, .{});
            } else if (mem.eql(u8, arg, "--")) {
                processing_options = false;
            } else {
                log.err("Unexpected option: {s}", .{arg});
            }
        } else {
            const sep_pos = mem.indexOfScalar(u8, arg, '-') orelse {
                log.err("Invalid GIR repository name: {s}", .{arg});
                return error.InvalidArguments;
            };
            try roots.append(.{
                .name = try allocator.dupe(u8, arg[0..sep_pos]),
                .version = try allocator.dupe(u8, arg[sep_pos + 1 ..]),
            });
        }
    }

    if (output_dir == null) {
        log.err("No output directory provided", .{});
        return error.InvalidArguments;
    }
    var src_out_dir = try output_dir.?.makeOpenPath("src", .{});
    defer src_out_dir.close();

    const repositories = try gir.findRepositories(allocator, gir_path.items, roots.items);
    defer allocator.free(repositories);
    defer for (repositories) |*repository| repository.deinit();
    try translate.createBindings(allocator, repositories, bindings_path.items, extensions_path.items, src_out_dir);
    try translate.createBuildFile(allocator, repositories, output_dir.?);
    if (abi_test_output_dir) |dir| {
        try translate.createAbiTests(allocator, repositories, dir);
    }
}
