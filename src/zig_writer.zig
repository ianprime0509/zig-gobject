const std = @import("std");
const compat = @import("compat.zig");

pub fn zigWriter(out: anytype) ZigWriter(@TypeOf(out)) {
    return .{ .out = out };
}

pub fn ZigWriter(comptime Writer: type) type {
    return struct {
        out: Writer,

        const Self = @This();
        pub const Error = Writer.Error;

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
        pub fn print(w: Self, comptime fmt: []const u8, args: anytype) Error!void {
            @setEvalBranchQuota(100_000);
            const arg_fields = compat.typeInfo(@TypeOf(args)).@"struct".fields;

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
                    try w.out.writeAll(fmt[start..i]);
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
                                    '\t' => try w.out.writeAll("    "),
                                    else => try w.out.writeByte(char),
                                }
                            }
                        } else {
                            try w.out.print("{}", .{arg});
                        }
                        current_arg += 1;
                    },
                    'S' => {
                        const arg = @field(args, arg_fields[current_arg].name);
                        try w.out.print("\"{}\"", .{std.zig.fmtEscapes(arg)});
                        current_arg += 1;
                    },
                    'I' => {
                        const arg = @field(args, arg_fields[current_arg].name);
                        // zig.fmtId does not escape primitive type names
                        if (std.zig.isValidId(arg) and !std.zig.primitives.isPrimitive(arg)) {
                            try w.out.print("{s}", .{arg});
                        } else {
                            try w.out.print("@\"{}\"", .{std.zig.fmtEscapes(arg)});
                        }
                        current_arg += 1;
                    },
                    else => @compileError("illegal format character: " ++ &[_]u8{fmt[i + 1]}),
                }
            }

            if (i > start) {
                try w.out.writeAll(fmt[start..i]);
            }

            if (current_arg != arg_fields.len) {
                @compileError("unused arguments remaining");
            }
        }
    };
}

inline fn isString(comptime T: type) bool {
    return switch (compat.typeInfo(T)) {
        .pointer => |pointer| if (pointer.size == .Slice)
            pointer.child == u8
        else if (pointer.size == .One)
            switch (compat.typeInfo(pointer.child)) {
                .array => |array| array.child == u8,
                else => false,
            }
        else
            false,
        else => false,
    };
}

test "print" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    var w = zigWriter(buf.writer());
    try w.print("const std = @import($S);\n\n", .{"std"});
    try w.print("pub fn $I() void {\n", .{"main"});
    try w.print("std.debug.print($S, .{$S});\n", .{ "Hello, {}!", "world" });
    try w.print("}\n", .{});
    try std.testing.expectEqualStrings(
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\std.debug.print("Hello, {}!", .{"world"});
        \\}
        \\
    , buf.items);
}
