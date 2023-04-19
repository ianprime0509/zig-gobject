const std = @import("std");
const testing = std.testing;
const zig = std.zig;

pub fn zigWriter(out: anytype) ZigWriter(@TypeOf(out)) {
    return .{ .out = out };
}

pub fn ZigWriter(comptime Writer: type) type {
    return struct {
        out: Writer,
        indent: usize = 0,
        needs_indent: bool = true,

        const Self = @This();
        pub const Error = Writer.Error;

        /// Prints Zig code to the output using the provided format string and
        /// arguments.
        ///
        /// Placeholders in the format string look like `$?`, where `?` may be
        /// any of the following:
        /// - `$`: a literal `$` character
        /// - `L`: the literal value of the argument (no escaping)
        /// - `S`: a string literal with the argument as its text
        /// - `I`: an identifier, escaped using raw identifier syntax if needed
        /// - `{`: a literal `{`, but increases the indent level by one
        /// - `}`: a literal `}`, but decreases the indent level by one
        /// The syntax here is inspired by JavaPoet.
        ///
        /// This is a much simpler implementation than Zig's usual format
        /// function and could use better design and error handling if it's ever
        /// made into its own project.
        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) Error!void {
            const arg_fields = @typeInfo(@TypeOf(args)).Struct.fields;

            comptime var current_arg = 0;
            comptime var i = 0;
            comptime var start = 0;

            inline while (i < fmt.len) : (i += 1) {
                if (fmt[i] == '\n') {
                    if (i > start) {
                        if (self.needs_indent) {
                            try self.writeIndent();
                        }
                        _ = try self.out.write(fmt[start..i]);
                    }
                    // Need to include indentation after the newline
                    _ = try self.out.write("\n");
                    start = i + 1;
                    self.needs_indent = true;
                    continue;
                }
                if (fmt[i] != '$') {
                    // Normal literal content
                    continue;
                }
                if (i + 1 == fmt.len) {
                    @compileError("unterminated placeholder");
                }
                if (i > start) {
                    if (self.needs_indent) {
                        try self.writeIndent();
                        self.needs_indent = false;
                    }
                    _ = try self.out.write(fmt[start..i]);
                }

                start = i + 2;
                switch (fmt[i + 1]) {
                    '$' => {
                        // Use the second $ as the beginning of literal content
                        start = i + 1;
                    },
                    'L' => {
                        if (self.needs_indent) {
                            try self.writeIndent();
                            self.needs_indent = false;
                        }
                        const arg = @field(args, arg_fields[current_arg].name);
                        const arg_type_info = @typeInfo(@TypeOf(arg));
                        if (arg_type_info == .Pointer and arg_type_info.Pointer.size == .Slice and arg_type_info.Pointer.child == u8) {
                            try self.out.print("{s}", .{arg});
                        } else {
                            try self.out.print("{}", .{arg});
                        }
                        current_arg += 1;
                    },
                    'S' => {
                        if (self.needs_indent) {
                            try self.writeIndent();
                            self.needs_indent = false;
                        }
                        const arg = @field(args, arg_fields[current_arg].name);
                        try self.out.print("\"{}\"", .{zig.fmtEscapes(arg)});
                        current_arg += 1;
                    },
                    'I' => {
                        if (self.needs_indent) {
                            try self.writeIndent();
                            self.needs_indent = false;
                        }
                        const arg = @field(args, arg_fields[current_arg].name);
                        try self.out.print("{}", .{zig.fmtId(arg)});
                        current_arg += 1;
                    },
                    '{' => {
                        // Use the { as the beginning of literal content
                        start = i + 1;
                        self.indent += 1;
                    },
                    '}' => {
                        // Use the } as the beginning of literal content
                        start = i + 1;
                        self.indent -|= 1;
                    },
                    else => @compileError("illegal format character: " ++ &[_]u8{fmt[i + 1]}),
                }
            }

            if (i > start) {
                if (self.needs_indent) {
                    try self.writeIndent();
                    self.needs_indent = false;
                }
                _ = try self.out.write(fmt[start..i]);
            }

            if (current_arg != arg_fields.len) {
                @compileError("unused arguments remaining");
            }
        }

        fn writeIndent(self: *Self) Error!void {
            for (0..self.indent) |_| {
                _ = try self.out.write("    ");
            }
        }
    };
}

test "print" {
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    var w = zigWriter(buf.writer());
    try w.print("const std = @import($S);\n\n", .{"std"});
    try w.print("pub fn $I() void ${\n", .{"main"});
    try w.print("std.debug.print($S, .{$S});\n", .{ "Hello, {}!", "world" });
    try w.print("$}\n", .{});
    try testing.expectEqualStrings(
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, {}!", .{"world"});
        \\}
        \\
    , buf.items);
}

test {
    testing.refAllDecls(@This());
}
