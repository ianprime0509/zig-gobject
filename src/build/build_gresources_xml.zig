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
    var output = std.ArrayList(u8).init(arena);
    try output.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?><gresources>");

    var i: usize = 1;
    var seen_prefix = false;
    var seen_preprocessor = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--prefix=")) {
            if (seen_prefix) {
                try output.appendSlice("</gresource>");
            }
            try output.writer().print("<gresource prefix=\"{}\">", .{fmtXml(arg["--prefix=".len..])});
            seen_prefix = true;
        } else if (std.mem.startsWith(u8, arg, "--alias=")) {
            try output.writer().print("<file alias=\"{}\"", .{fmtXml(arg["--alias=".len..])});
        } else if (std.mem.eql(u8, arg, "--compressed")) {
            try output.appendSlice(" compressed=\"true\"");
        } else if (std.mem.startsWith(u8, arg, "--preprocess=")) {
            if (seen_preprocessor) {
                try output.writer().print(",{}", .{fmtXml(arg["--preprocess=".len..])});
            } else {
                try output.writer().print(" preprocess=\"{}", .{fmtXml(arg["--preprocess=".len..])});
            }
            seen_preprocessor = true;
        } else if (std.mem.startsWith(u8, arg, "--path=")) {
            if (seen_preprocessor) {
                try output.append('"');
            }
            try output.writer().print(">{}</file>", .{fmtXml(arg["--path=".len..])});
            seen_preprocessor = false;
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            output_path = arg["--output=".len..];
        } else {
            return error.UnrecognizedOption;
        }
    }

    if (seen_prefix) {
        try output.appendSlice("</gresource>");
    }
    try output.appendSlice("</gresources>");

    try std.fs.cwd().writeFile(.{
        .sub_path = output_path orelse return error.MissingOutput,
        .data = output.items,
    });
}

fn fmtXml(s: []const u8) std.fmt.Formatter(formatXml) {
    return .{ .data = s };
}

fn formatXml(s: []const u8, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

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
