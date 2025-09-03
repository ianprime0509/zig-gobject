const std = @import("std");
const Allocator = std.mem.Allocator;
const compat = @import("compat.zig");

raw: std.ArrayList(u8),
gpa: Allocator,

const ZigWriter = @This();

pub fn init(gpa: Allocator) ZigWriter {
    return .{
        .raw = .empty,
        .gpa = gpa,
    };
}

pub fn deinit(w: *ZigWriter) void {
    w.raw.deinit(w.gpa);
    w.* = undefined;
}

/// Prints Zig code to the output using the provided format string and
/// arguments.
///
/// Placeholders in the format string look like `$?`, where `?` may be
/// any of the following:
///
/// - `$`: a literal `$` character
/// - `L`: the literal value of the argument (no escaping)
/// - `S`: a string literal with the argument as its text
/// - `I`: an identifier, escaped using raw identifier syntax if needed
///
/// The syntax here is inspired by JavaPoet.
///
/// This is a much simpler implementation than Zig's usual format
/// function and could use better design and error handling if it's ever
/// made into its own project.
pub fn print(w: *ZigWriter, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    @setEvalBranchQuota(100_000);
    const arg_fields = @typeInfo(@TypeOf(args)).@"struct".fields;

    comptime var current_arg = 0;
    comptime var i = 0;
    comptime var start = 0;

    inline while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '$') {
            // Normal literal content
            continue;
        }
        if (i + 1 == fmt.len) {
            @compileError("unterminated placeholder");
        }
        if (i > start) {
            try w.raw.appendSlice(w.gpa, fmt[start..i]);
        }

        start = i + 2;
        switch (fmt[i + 1]) {
            '$' => {
                // Use the second $ as the beginning of literal content
                start = i + 1;
            },
            'L' => {
                const arg = @field(args, arg_fields[current_arg].name);
                if (isString(@TypeOf(arg))) {
                    for (arg) |char| {
                        switch (char) {
                            // Zig is very tab-hostile, so we have to replace tabs with spaces.
                            // This is most relevant when translating documentation.
                            '\t' => try w.raw.appendSlice(w.gpa, "    "),
                            else => try w.raw.append(w.gpa, char),
                        }
                    }
                } else {
                    try w.raw.print(w.gpa, "{}", .{arg});
                }
                current_arg += 1;
            },
            'S' => {
                const arg = @field(args, arg_fields[current_arg].name);
                try w.raw.print(w.gpa, "\"{f}\"", .{std.zig.fmtString(arg)});
                current_arg += 1;
            },
            'I' => {
                const arg = @field(args, arg_fields[current_arg].name);
                // zig.fmtId does not escape primitive type names
                if (std.zig.isValidId(arg) and !std.zig.primitives.isPrimitive(arg)) {
                    try w.raw.appendSlice(w.gpa, arg);
                } else {
                    try w.raw.print(w.gpa, "@\"{f}\"", .{std.zig.fmtString(arg)});
                }
                current_arg += 1;
            },
            else => @compileError("illegal format character: " ++ &[_]u8{fmt[i + 1]}),
        }
    }

    if (i > start) {
        try w.raw.appendSlice(w.gpa, fmt[start..i]);
    }

    if (current_arg != arg_fields.len) {
        @compileError("unused arguments remaining");
    }
}

pub fn toFormatted(w: *ZigWriter) Allocator.Error![]u8 {
    try w.raw.append(w.gpa, 0);
    defer w.raw.clearAndFree(w.gpa);
    var ast: std.zig.Ast = try .parse(w.gpa, w.raw.items[0 .. w.raw.items.len - 1 :0], .zig);
    defer ast.deinit(w.gpa);
    var fmt_source: std.Io.Writer.Allocating = .init(w.gpa);
    defer fmt_source.deinit();
    ast.render(w.gpa, &fmt_source.writer, .{}) catch |err| switch (err) {
        error.OutOfMemory, error.WriteFailed => return error.OutOfMemory,
    };
    return try fmt_source.toOwnedSlice();
}

test ZigWriter {
    var w: ZigWriter = .init(std.testing.allocator);
    defer w.deinit();
    try w.print("const std = @import($S);\n\n", .{"std"});
    try w.print("pub fn $I() void {\n", .{"main"});
    try w.print("std.debug.print($S, .{$S});\n", .{ "Hello, {}!", "world" });
    try w.print("}\n", .{});
    const fmt_source = try w.toFormatted();
    defer std.testing.allocator.free(fmt_source);
    try std.testing.expectEqualStrings(
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, {}!", .{"world"});
        \\}
        \\
    , fmt_source);
}

inline fn isString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| if (pointer.size == .slice)
            pointer.child == u8
        else if (pointer.size == .one)
            switch (@typeInfo(pointer.child)) {
                .array => |array| array.child == u8,
                else => false,
            }
        else
            false,
        else => false,
    };
}
