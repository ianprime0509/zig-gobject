const gobject = @import("gobject");

const std = @import("std");
const bindings = @import("bindings.zig");
const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const Value = gobject.Value;

test "bindings" {
    bindings.refAllBindings(gobject);
}

test "Value.new" {
    try testValueNew(i8, -123, Value.getSchar, Value.setSchar);
    try testValueNew(u8, 123, Value.getUchar, Value.setUchar);
    try testValueNew(bool, true, Value.getBoolean, Value.setBoolean);
    try testValueNew(c_int, -123, Value.getInt, Value.setInt);
    try testValueNew(c_uint, 123, Value.getUint, Value.setUint);
    try testValueNew(c_long, -123, Value.getLong, Value.setLong);
    try testValueNew(c_ulong, 123, Value.getUlong, Value.setUlong);
    try testValueNew(i64, -(1 << 48), Value.getInt64, Value.setInt64);
    try testValueNew(u64, 1 << 48, Value.getUint64, Value.setUint64);
    try testValueNew(f32, 3.14, Value.getFloat, Value.setFloat);
    try testValueNew(f64, 3.1415926, Value.getDouble, Value.setDouble);
}

test "Value.new([*:0]const u8)" {
    var value = Value.new([*:0]const u8);
    defer value.unset();
    value.setString("Hello, world!");
    try expectEqualStrings("Hello, world!", std.mem.sliceTo(value.getString().?, 0));
}

test "Value.new(*anyopaque)" {
    var value = Value.new(*anyopaque);
    defer value.unset();
    var something: i32 = 123;
    value.setPointer(&something);
    try expectEqual(@as(?*anyopaque, &something), value.getPointer());
}

fn testValueNew(comptime T: type, data: T, getter: fn (*const Value) callconv(.C) T, setter: fn (*Value, T) callconv(.C) void) !void {
    var value = Value.new(T);
    defer value.unset();
    setter(&value, data);
    try expectEqual(data, getter(&value));
}

test "Object subclass" {
    const Subclass = extern struct {
        parent_instance: Parent,

        pub const Parent = gobject.Object;
        const Self = @This();

        pub const Private = struct {
            some_value: i32,

            pub var offset: c_int = 0;
        };

        pub const getType = gobject.registerType(Self, .{});

        pub fn new() *Self {
            return Self.newWith(.{});
        }

        pub fn init(self: *Self, _: *Self.Class) callconv(.C) void {
            self.private().some_value = 123;
        }

        pub fn getSomeValue(self: *Self) i32 {
            return self.private().some_value;
        }

        pub usingnamespace Parent.Methods(Self);

        pub const Class = extern struct {
            parent_class: Parent.Class,

            pub const Instance = Self;

            pub usingnamespace Parent.Class.Methods(Class);
            pub usingnamespace Parent.VirtualMethods(Class, Self);
        };
    };

    const obj = Subclass.new();
    defer obj.unref();
    try expectEqual(@as(i32, 123), obj.getSomeValue());
}
