const std = @import("std");
const fs = std.fs;

const gir = @import("gir.zig");
const translate = @import("translate.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var in_dir = try fs.cwd().openDir("lib/gir-files", .{});
    var extras_dir = try fs.cwd().openDir("gir-extras", .{});
    var out_dir = try fs.cwd().openDir("src/gir-out", .{});
    defer out_dir.close();
    try translate.translate(gpa.allocator(), in_dir, extras_dir, out_dir, &.{"Gtk-4.0.gir"});
}
