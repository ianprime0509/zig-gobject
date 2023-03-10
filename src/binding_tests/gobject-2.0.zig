const std = @import("std");
const gobject = @import("../gir-out/gobject-2.0.zig");
const testing = std.testing;
const Value = gobject.Value;

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
    try testing.expectEqualStrings("Hello, world!", std.mem.sliceTo(value.getString(), 0));
}

test "Value.new(*anyopaque)" {
    var value = Value.new(*anyopaque);
    defer value.unset();
    var something: i32 = 123;
    value.setPointer(&something);
    try testing.expectEqual(@as(?*anyopaque, &something), value.getPointer());
}

fn testValueNew(comptime T: type, data: T, getter: fn (*const Value) callconv(.C) T, setter: fn (*Value, T) callconv(.C) void) !void {
    var value = Value.new(T);
    defer value.unset();
    setter(&value, data);
    try testing.expectEqual(data, getter(&value));
}
