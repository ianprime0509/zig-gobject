const std = @import("std");
const fs = std.fs;
const log = std.log;
const process = std.process;

const gir = @import("gir.zig");
const translate = @import("translate.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);
    if (args.len < 4) {
        return error.NotEnoughArguments;
    }
    var in_dir = try fs.cwd().openDir(args[1], .{});
    defer in_dir.close();
    var extras_dir = try fs.cwd().openDir(args[2], .{});
    defer extras_dir.close();
    var out_dir = try fs.cwd().makeOpenPath(args[3], .{});
    defer out_dir.close();

    const translation = try translate.translate(gpa.allocator(), .{
        .input = in_dir,
        .extras = extras_dir,
        .output = out_dir,
    }, args[4..]);
    defer translation.deinit();
}
