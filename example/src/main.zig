const std = @import("std");

const Example = struct {
    name: []const u8,
    main: *const fn (init: std.process.Init) void,
};

const examples: []const Example = &.{
    .{ .name = "Hello world", .main = &@import("hello_world.zig").main },
    .{ .name = "Custom drawing", .main = &@import("custom_drawing.zig").main },
    .{ .name = "Custom class", .main = &@import("custom_class.zig").main },
    .{ .name = "PangoCairo text rendering", .main = &@import("pango_cairo.zig").main },
    .{ .name = "List view", .main = &@import("list_view.zig").main },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    const stdin = &stdin_reader.interface;
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("Available examples:\n");
    var i: usize = 0;
    for (examples) |example| {
        try stdout.print("{} - {s}\n", .{ i, example.name });
        i += 1;
    }
    try stdout.writeAll("Choose an example: ");
    try stdout.flush();

    const input = try stdin.takeDelimiterExclusive('\n');
    const choice = try std.fmt.parseInt(usize, input, 10);
    if (choice >= examples.len) {
        return error.OutOfBounds;
    }
    examples[choice].main(init);
}
