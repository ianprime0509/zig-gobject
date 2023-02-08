const std = @import("std");
const glib = @import("./gir-out/glib.zig");

pub fn main() void {
    var i: c_int = 2;
    std.log.info("i = {}", .{i});
    _ = glib.atomicIntAdd(&i, 1);
    std.log.info("i = {}", .{i});
}
