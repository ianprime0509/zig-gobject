const std = @import("std");
const gir = @import("gir.zig");
const translate = @import("translate.zig");
const fs = std.fs;
const log = std.log;
const mem = std.mem;
const process = std.process;
const testing = std.testing;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);
    if (args.len < 4) {
        return error.NotEnoughArguments;
    }

    var search_path = ArrayListUnmanaged(fs.Dir){};
    defer {
        for (search_path.items) |*dir| dir.close();
        search_path.deinit(allocator);
    }
    var search_path_iter = mem.split(u8, args[1], &[_]u8{fs.path.delimiter});
    while (search_path_iter.next()) |path| {
        try search_path.append(allocator, try fs.cwd().openDir(path, .{}));
    }

    var extras_dir = try fs.cwd().openDir(args[2], .{});
    defer extras_dir.close();

    var out_dir = try fs.cwd().makeOpenPath(args[3], .{});
    defer out_dir.close();
    var src_out_dir = try out_dir.makeOpenPath("src", .{});

    var repositories = try translate.findRepositories(allocator, search_path.items, args[4..]);
    defer repositories.deinit();

    try translate.translate(&repositories, extras_dir, src_out_dir);
    try translate.createBuildFile(&repositories, out_dir);
}

test {
    testing.refAllDecls(@This());
}
