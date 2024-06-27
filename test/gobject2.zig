const gobject = @import("gobject");

const std = @import("std");
const bindings = @import("bindings.zig");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "bindings" {
    bindings.refAllBindings(gobject);
}

test "isAssignableFrom" {
    try expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.Object));
    try expect(gobject.ext.isAssignableFrom(gobject.TypeInstance, gobject.Object));
    try expect(!gobject.ext.isAssignableFrom(gobject.Object, gobject.TypeInstance));
    try expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.InitiallyUnowned));
    try expect(!gobject.ext.isAssignableFrom(gobject.InitiallyUnowned, gobject.Object));
    try expect(gobject.ext.isAssignableFrom(gobject.TypeInstance, gobject.InitiallyUnowned));
    try expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.TypePlugin));
    try expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.TypeModule));
    try expect(gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.InitiallyUnowned.Class));
    try expect(gobject.ext.isAssignableFrom(gobject.TypeClass, gobject.InitiallyUnowned.Class));
    try expect(!gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.TypeClass));
    try expect(gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.InitiallyUnowned.Class));
    try expect(!gobject.ext.isAssignableFrom(gobject.InitiallyUnowned.Class, gobject.Object.Class));
}

test "Value.new" {
    try testValueNew(i8, -123, gobject.Value.getSchar, gobject.Value.setSchar);
    try testValueNew(u8, 123, gobject.Value.getUchar, gobject.Value.setUchar);
    try testValueNew(c_int, -123, gobject.Value.getInt, gobject.Value.setInt);
    try testValueNew(c_uint, 123, gobject.Value.getUint, gobject.Value.setUint);
    try testValueNew(c_long, -123, gobject.Value.getLong, gobject.Value.setLong);
    try testValueNew(c_ulong, 123, gobject.Value.getUlong, gobject.Value.setUlong);
    try testValueNew(i64, -(1 << 48), gobject.Value.getInt64, gobject.Value.setInt64);
    try testValueNew(u64, 1 << 48, gobject.Value.getUint64, gobject.Value.setUint64);
    try testValueNew(f32, 3.14, gobject.Value.getFloat, gobject.Value.setFloat);
    try testValueNew(f64, 3.1415926, gobject.Value.getDouble, gobject.Value.setDouble);
}

test "Value.new(bool)" {
    var value = gobject.ext.Value.new(bool);
    defer value.unset();
    value.setBoolean(1);
    try expectEqual(@as(c_int, 1), value.getBoolean());
}

test "Value.new([*:0]const u8)" {
    var value = gobject.ext.Value.new([*:0]const u8);
    defer value.unset();
    value.setString("Hello, world!");
    try expectEqualStrings("Hello, world!", std.mem.span(value.getString().?));
}

test "Value.new([:0]const u8)" {
    var value = gobject.ext.Value.new([:0]const u8);
    defer value.unset();
    value.setString("Hello, world!");
    try expectEqualStrings("Hello, world!", std.mem.span(value.getString().?));
}

fn testValueNew(
    comptime T: type,
    data: T,
    getter: fn (*const gobject.Value) callconv(.C) T,
    setter: fn (*gobject.Value, T) callconv(.C) void,
) !void {
    var value = gobject.ext.Value.new(T);
    defer value.unset();
    setter(&value, data);
    try expectEqual(data, getter(&value));
}

test "Object subclass" {
    const Subclass = extern struct {
        parent_instance: Parent,

        pub const Parent = gobject.Object;
        const Self = @This();

        const Private = struct {
            some_value: i32,

            var offset: c_int = 0;
        };

        pub const getGObjectType = gobject.ext.defineClass(Self, .{
            .instanceInit = &init,
            .private = .{ .Type = Private, .offset = &Private.offset },
        });

        pub fn new() *Self {
            return gobject.ext.newInstance(Self, .{});
        }

        pub fn as(self: *Self, comptime T: type) *T {
            return gobject.ext.as(T, self);
        }

        pub fn ref(self: *Self) void {
            gobject.Object.ref(self.as(gobject.Object));
        }

        pub fn unref(self: *Self) void {
            gobject.Object.unref(self.as(gobject.Object));
        }

        fn init(self: *Self, _: *Self.Class) callconv(.C) void {
            self.private().some_value = 123;
        }

        pub fn getSomeValue(self: *Self) i32 {
            return self.private().some_value;
        }

        fn private(self: *Self) *Private {
            return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
        }

        pub const Class = extern struct {
            parent_class: Parent.Class,

            pub const Instance = Self;

            pub fn as(self: *Class, comptime T: type) *T {
                return gobject.ext.as(T, self);
            }
        };
    };

    const obj = Subclass.new();
    defer obj.unref();
    try expectEqual(123, obj.getSomeValue());
    try expect(gobject.ext.isA(obj, gobject.Object));
    try expect(gobject.ext.cast(gobject.Object, obj) != null);
}

test "boxed type" {
    const MyBoxed = struct {
        a: u32,
        b: u32,

        pub const getGObjectType = gobject.ext.defineBoxed(@This(), .{});
    };

    const value1: *const MyBoxed = &.{ .a = 123, .b = 456 };
    const value2: *MyBoxed = @ptrCast(@alignCast(gobject.boxedCopy(MyBoxed.getGObjectType(), value1)));
    defer gobject.boxedFree(MyBoxed.getGObjectType(), value2);
    try expectEqual(123, value2.a);
    try expectEqual(456, value2.b);
}

test "enum type" {
    const MyEnum = enum(c_int) {
        one = 1,
        two = 2,
        three = 3,

        pub const getGObjectType = gobject.ext.defineEnum(@This(), .{});
    };

    const enum_type_class: *gobject.EnumClass = @ptrCast(gobject.TypeClass.ref(MyEnum.getGObjectType()));
    try expectEqual(1, enum_type_class.minimum);
    try expectEqual(3, enum_type_class.maximum);
    try expectEqual(3, enum_type_class.n_values);
}

test "flags type" {
    const MyFlags = packed struct(c_uint) {
        one: bool = false,
        two: i1 = -1,
        _padding0: u2 = 0,
        three: u1 = 1,
        _padding1: @Type(.{ .Int = .{
            .signedness = .unsigned,
            .bits = @bitSizeOf(c_uint) - 5,
        } }) = 0,

        pub const getGObjectType = gobject.ext.defineFlags(@This(), .{});
    };

    const flags_type_class: *gobject.FlagsClass = @ptrCast(gobject.TypeClass.ref(MyFlags.getGObjectType()));
    try expectEqual(0b10011, flags_type_class.mask);
    try expectEqual(3, flags_type_class.n_values);
}
