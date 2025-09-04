//! A simple wrapper to build a `gresources.xml` description from command-line
//! arguments.
//!
//! This program is only meant to be invoked internally as part of the
//! zig-gobject build helper logic, hence, having a "user-friendly" interface
//! is not a goal.

const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    var output_path: ?[]const u8 = null;
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(arena, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gresources>");

    var i: usize = 1;
    var seen_prefix = false;
    var seen_preprocessor = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--prefix=")) {
            if (seen_prefix) {
                try output.appendSlice(arena, "</gresource>");
            }
            try output.print(arena, "<gresource prefix=\"{f}\">", .{fmtXml(arg["--prefix=".len..])});
            seen_prefix = true;
        } else if (std.mem.startsWith(u8, arg, "--alias=")) {
            try output.print(arena, "<file alias=\"{f}\"", .{fmtXml(arg["--alias=".len..])});
        } else if (std.mem.eql(u8, arg, "--compressed")) {
            try output.appendSlice(arena, " compressed=\"true\"");
        } else if (std.mem.startsWith(u8, arg, "--preprocess=")) {
            if (seen_preprocessor) {
                try output.print(arena, ",{f}", .{fmtXml(arg["--preprocess=".len..])});
            } else {
                try output.print(arena, " preprocess=\"{f}", .{fmtXml(arg["--preprocess=".len..])});
            }
            seen_preprocessor = true;
        } else if (std.mem.startsWith(u8, arg, "--path=")) {
            if (seen_preprocessor) {
                try output.append(arena, '"');
            }
            try output.print(arena, ">{f}</file>", .{fmtXml(arg["--path=".len..])});
            seen_preprocessor = false;
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            output_path = arg["--output=".len..];
        } else {
            return error.UnrecognizedOption;
        }
    }

    if (seen_prefix) {
        try output.appendSlice(arena, "</gresource>");
    }
    try output.appendSlice(arena, "</gresources>");

    try std.fs.cwd().writeFile(.{
        .sub_path = output_path orelse return error.MissingOutput,
        .data = output.items,
    });
}

fn fmtXml(s: []const u8) std.fmt.Alt([]const u8, formatXml) {
    return .{ .data = s };
}

fn formatXml(s: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var start: usize = 0;
    while (std.mem.indexOfAnyPos(u8, s, start, "&<\"")) |pos| {
        try writer.writeAll(s[start..pos]);
        try writer.writeAll(switch (s[pos]) {
            '&' => "&amp;",
            '<' => "&lt;",
            '"' => "&quot;",
            else => unreachable,
        });
        start = pos + 1;
    }
    try writer.writeAll(s[start..]);
}
