const std = @import("std");

const Example = struct {
    name: []const u8,
    main: *const fn () void,
};

const examples: []const Example = &.{
    .{ .name = "Hello world", .main = &@import("hello_world.zig").main },
    // .{ .name = "Custom drawing", .main = &@import("examples/custom_drawing.zig").main },
    .{ .name = "Custom class", .main = &@import("custom_class.zig").main },
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    _ = try stdout.write("Available examples:\n");
    var i: usize = 0;
    for (examples) |example| {
        try stdout.print("{} - {s}\n", .{ i, example.name });
        i += 1;
    }
    _ = try stdout.write("Choose an example: ");

    var buf: [16]u8 = undefined;
    const input = try stdin.readUntilDelimiter(&buf, '\n');
    const choice = try std.fmt.parseInt(usize, input, 10);
    if (choice >= examples.len) {
        return error.OutOfBounds;
    }
    examples[choice].main();
}
