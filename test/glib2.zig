const glib = @import("glib");

const std = @import("std");
const bindings = @import("bindings.zig");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "bindings" {
    bindings.refAllBindings(glib);
}

test "create/destroy" {
    const T = struct { a: u32, b: u64 };
    const value = glib.ext.create(T);
    defer glib.ext.destroy(value);
    value.a = 123;
    value.b = 456;
    try expectEqual(123, value.a);
    try expectEqual(456, value.b);
}

test "alloc/free" {
    const slice = glib.ext.alloc(u32, 3);
    defer glib.ext.free(slice);
    slice[0] = 1;
    slice[1] = 2;
    slice[2] = 3;
    try expectEqual(1, slice[0]);
    try expectEqual(2, slice[1]);
    try expectEqual(3, slice[2]);
}

test "Bytes.getDataSlice" {
    const null_ptr = glib.Bytes.new(null, 0);
    defer null_ptr.unref();
    try expectEqualStrings("", glib.ext.Bytes.getDataSlice(null_ptr));

    const empty = glib.ext.Bytes.newFromSlice("");
    defer empty.unref();
    try expectEqualStrings("", glib.ext.Bytes.getDataSlice(empty));

    const non_empty = glib.ext.Bytes.newFromSlice("Hello");
    defer non_empty.unref();
    try expectEqualStrings("Hello", glib.ext.Bytes.getDataSlice(non_empty));
}

test "Variant.newFrom" {
    try testVariantNewFrom(u8, 123, glib.Variant.getByte);
    try testVariantNewFrom(i16, -12345, glib.Variant.getInt16);
    try testVariantNewFrom(i32, -(1 << 24), glib.Variant.getInt32);
    try testVariantNewFrom(i64, -(1 << 48), glib.Variant.getInt64);
    try testVariantNewFrom(u16, 12345, glib.Variant.getUint16);
    try testVariantNewFrom(u32, 1 << 24, glib.Variant.getUint32);
    try testVariantNewFrom(u64, 1 << 48, glib.Variant.getUint64);
    try testVariantNewFrom(f64, 3.1415926, glib.Variant.getDouble);
}

test "Variant.newFrom(bool)" {
    const variant = glib.ext.Variant.newFrom(true);
    defer variant.unref();
    try expectEqual(1, variant.getBoolean());
}

test "Variant.newFrom(string literal)" {
    const variant = glib.ext.Variant.newFrom("Hello, world!");
    defer variant.unref();
    var len: usize = undefined;
    const string = variant.getString(&len);
    try expectEqualStrings("Hello, world!", string[0..len]);
}

test "Variant.newFrom([*:0]const u8)" {
    const str: [*:0]const u8 = "Hello, world!";
    const variant = glib.ext.Variant.newFrom(str);
    defer variant.unref();
    var len: usize = undefined;
    const string = variant.getString(&len);
    try expectEqualStrings("Hello, world!", string[0..len]);
}

test "Variant.newFrom([:0]const u8)" {
    const str: [:0]const u8 = "Hello, world!";
    const variant = glib.ext.Variant.newFrom(str);
    defer variant.unref();
    var len: usize = undefined;
    const string = variant.getString(&len);
    try expectEqualStrings("Hello, world!", string[0..len]);
}

test "Variant.newFrom([4]u16)" {
    const arr: [4]u16 = .{ 1, 2, 3, 4 };
    const variant = glib.ext.Variant.newFrom(arr);
    defer variant.unref();
    try expectEqual(arr.len, variant.nChildren());
    for (arr, 0..) |item, i| {
        const child = variant.getChildValue(i);
        defer child.unref();
        try expectEqual(item, child.getUint16());
    }
}

test "Variant.newFrom([]const u32)" {
    const slice: []const u32 = &.{ 1, 2, 3, 4, 5 };
    const variant = glib.ext.Variant.newFrom(slice);
    defer variant.unref();
    try expectEqual(slice.len, variant.nChildren());
    for (slice, 0..) |item, i| {
        const child = variant.getChildValue(i);
        defer child.unref();
        try expectEqual(item, child.getUint32());
    }
}

test "Variant.newFrom(?i16)" {
    {
        const opt: ?i16 = -12345;
        const variant = glib.ext.Variant.newFrom(opt);
        defer variant.unref();
        const maybe_child = variant.getMaybe();
        defer if (maybe_child) |child| child.unref();
        try expect(maybe_child != null);
        try expectEqual(-12345, maybe_child.?.getInt16());
    }

    {
        const opt: ?i16 = null;
        const variant = glib.ext.Variant.newFrom(opt);
        defer variant.unref();
        try expectEqual(null, variant.getMaybe());
    }
}

test "Variant.newFrom(struct{u32, u64, i64})" {
    const tuple: struct { u32, u64, i64 } = .{ 1, 2, -3 };
    const variant = glib.ext.Variant.newFrom(tuple);
    defer variant.unref();
    try expectEqual(tuple.len, variant.nChildren());
    {
        const child = variant.getChildValue(0);
        defer child.unref();
        try expectEqual(tuple[0], child.getUint32());
    }
    {
        const child = variant.getChildValue(1);
        defer child.unref();
        try expectEqual(tuple[1], child.getUint64());
    }
    {
        const child = variant.getChildValue(2);
        defer child.unref();
        try expectEqual(tuple[2], child.getInt64());
    }
}

fn testVariantNewFrom(
    comptime T: type,
    data: T,
    getter: fn (*glib.Variant) callconv(.C) T,
) !void {
    const variant = glib.ext.Variant.newFrom(data);
    defer variant.unref();
    try expectEqual(data, getter(variant));
}
