const std = @import("std");
const gir = @import("gir.zig");
const translate = @import("translate.zig");
const fs = std.fs;
const io = std.io;
const log = std.log;
const mem = std.mem;
const process = std.process;
const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const usage =
    \\Usage: zig-gobject [options] [root...]
    \\
    \\Generates bindings for the given root namespaces and their dependencies.
    \\
    \\Options:
    \\  -h, --help                          Show this help
    \\      --extras-dir DIR                Add a directory to the extras search path
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
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try process.argsWithAllocator(allocator);
    _ = args.skip();

    var gir_path = ArrayListUnmanaged(fs.Dir){};
    defer for (gir_path.items) |*dir| dir.close();
    var extras_path = ArrayListUnmanaged(fs.Dir){};
    defer for (extras_path.items) |*dir| dir.close();
    var output_dir: ?fs.Dir = null;
    defer if (output_dir) |*dir| dir.close();
    var abi_test_output_dir: ?fs.Dir = null;
    defer if (abi_test_output_dir) |*dir| dir.close();
    var roots = ArrayListUnmanaged(gir.Include){};

    var processing_options = true;
    while (args.next()) |arg| {
        if (processing_options and mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                try io.getStdOut().writeAll(usage);
                return;
            } else if (mem.eql(u8, arg, "--extras-dir")) {
                const extras_dir_path = args.next() orelse {
                    log.err("Expected directory after --extras-dir", .{});
                    return error.InvalidArguments;
                };
                try extras_path.append(allocator, try fs.cwd().openDir(extras_dir_path, .{}));
            } else if (mem.eql(u8, arg, "--gir-dir")) {
                const gir_dir_path = args.next() orelse {
                    log.err("Expected directory after --gir-dir", .{});
                    return error.InvalidArguments;
                };
                try gir_path.append(allocator, try fs.cwd().openDir(gir_dir_path, .{}));
            } else if (mem.eql(u8, arg, "--output-dir")) {
                const output_dir_path = args.next() orelse {
                    log.err("Expected directory after --output-dir", .{});
                    return error.InvalidArguments;
                };
                if (output_dir) |*dir| dir.close();
                output_dir = try fs.cwd().makeOpenPath(output_dir_path, .{});
            } else if (mem.eql(u8, arg, "--abi-test-output-dir")) {
                const abi_test_output_dir_path = args.next() orelse {
                    log.err("Expected directory after --abi-test-output-dir", .{});
                    return error.InvalidArguments;
                };
                if (abi_test_output_dir) |*dir| dir.close();
                abi_test_output_dir = try fs.cwd().makeOpenPath(abi_test_output_dir_path, .{});
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
            try roots.append(allocator, .{
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
    try translate.createBindings(allocator, repositories, extras_path.items, src_out_dir);
    try translate.createBuildFile(allocator, repositories, output_dir.?);
    if (abi_test_output_dir) |dir| {
        try translate.createAbiTests(allocator, repositories, dir);
    }
}
