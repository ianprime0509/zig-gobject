const glib = @import("glib2");
const std = @import("std");

/// Creates a heap-allocated value of type `T` using `glib.malloc`. `T` must not
/// be zero-sized or aligned more than `std.c.max_align_t`.
pub fn create(comptime T: type) *T {
    if (@sizeOf(T) == 0) @compileError("zero-sized types not supported");
    if (@alignOf(T) > @alignOf(std.c.max_align_t)) @compileError("overaligned types not supported");
    return @ptrCast(@alignCast(glib.malloc(@sizeOf(T))));
}

test create {
    const T = struct { a: u32, b: u64 };
    const value = glib.ext.create(T);
    defer glib.ext.destroy(value);
    value.a = 123;
    value.b = 456;
    try std.testing.expectEqual(123, value.a);
    try std.testing.expectEqual(456, value.b);
}

/// Creates a heap-allocated copy of `value` using `glib.malloc`. `T` must not
/// be zero-sized or aligned more than `std.c.max_align_t`.
pub inline fn new(comptime T: type, value: T) *T {
    const new_value = create(T);
    new_value.* = value;
    return new_value;
}

test new {
    const T = struct { a: u32, b: u64 };
    const value = glib.ext.new(T, .{ .a = 123, .b = 456 });
    defer glib.ext.destroy(value);
    try std.testing.expectEqual(123, value.a);
    try std.testing.expectEqual(456, value.b);
}

/// Destroys a value created using `create`.
pub fn destroy(ptr: anytype) void {
    const type_info = @typeInfo(@TypeOf(ptr));
    if (type_info != .pointer or type_info.pointer.size != .one) @compileError("must be a single-item pointer");
    glib.freeSized(@ptrCast(ptr), @sizeOf(type_info.pointer.child));
}

test destroy {
    const T = struct { a: u32, b: u64 };
    const value = glib.ext.create(T);
    defer glib.ext.destroy(value);
    value.a = 123;
    value.b = 456;
    try std.testing.expectEqual(123, value.a);
    try std.testing.expectEqual(456, value.b);
}

/// Heap allocates a slice of `n` values of type `T` using `glib.mallocN`. `T`
/// must not be zero-sized or aligned more than `std.c.max_align_t`.
pub fn alloc(comptime T: type, n: usize) []T {
    if (@sizeOf(T) == 0) @compileError("zero-sized types not supported");
    if (@alignOf(T) > @alignOf(std.c.max_align_t)) @compileError("overaligned types not supported");
    const ptr: [*]T = @ptrCast(@alignCast(glib.mallocN(@sizeOf(T), n)));
    return ptr[0..n];
}

test alloc {
    const slice = glib.ext.alloc(u32, 3);
    defer glib.ext.free(slice);
    slice[0] = 1;
    slice[1] = 2;
    slice[2] = 3;
    try std.testing.expectEqual(1, slice[0]);
    try std.testing.expectEqual(2, slice[1]);
    try std.testing.expectEqual(3, slice[2]);
}

/// Frees a slice created using `alloc`.
pub fn free(ptr: anytype) void {
    const type_info = @typeInfo(@TypeOf(ptr));
    if (type_info != .pointer or type_info.pointer.size != .slice) @compileError("must be a slice");
    glib.freeSized(@ptrCast(ptr.ptr), @sizeOf(type_info.pointer.child) * ptr.len);
}

test free {
    const slice = glib.ext.alloc(u32, 3);
    defer glib.ext.free(slice);
    slice[0] = 1;
    slice[1] = 2;
    slice[2] = 3;
    try std.testing.expectEqual(1, slice[0]);
    try std.testing.expectEqual(2, slice[1]);
    try std.testing.expectEqual(3, slice[2]);
}

pub const Bytes = struct {
    /// Returns a new `Bytes` copying the given slice.
    pub fn newFromSlice(bytes: []const u8) *glib.Bytes {
        return glib.Bytes.new(bytes.ptr, bytes.len);
    }

    /// Returns the byte data in `bytes` as a slice.
    pub fn getDataSlice(bytes: *glib.Bytes) []const u8 {
        var size: usize = undefined;
        const maybe_ptr = bytes.getData(&size);
        return if (maybe_ptr) |ptr| ptr[0..size] else &.{};
    }

    test getDataSlice {
        const null_ptr = glib.Bytes.new(null, 0);
        defer null_ptr.unref();
        try std.testing.expectEqualStrings("", glib.ext.Bytes.getDataSlice(null_ptr));

        const empty = glib.ext.Bytes.newFromSlice("");
        defer empty.unref();
        try std.testing.expectEqualStrings("", glib.ext.Bytes.getDataSlice(empty));

        const non_empty = glib.ext.Bytes.newFromSlice("Hello");
        defer non_empty.unref();
        try std.testing.expectEqualStrings("Hello", glib.ext.Bytes.getDataSlice(non_empty));
    }
};

pub const Variant = struct {
    /// Returns a new `Variant` with the given contents.
    ///
    /// This does not take ownership of the value (if applicable).
    pub fn newFrom(contents: anytype) *glib.Variant {
        const T = @TypeOf(contents);
        const type_info = @typeInfo(T);
        if (T == bool) {
            return glib.Variant.newBoolean(@intFromBool(contents));
        } else if (T == u8) {
            return glib.Variant.newByte(contents);
        } else if (T == i16) {
            return glib.Variant.newInt16(contents);
        } else if (T == i32) {
            return glib.Variant.newInt32(contents);
        } else if (T == i64) {
            return glib.Variant.newInt64(contents);
        } else if (T == u16) {
            return glib.Variant.newUint16(contents);
        } else if (T == u32) {
            return glib.Variant.newUint32(contents);
        } else if (T == u64) {
            return glib.Variant.newUint64(contents);
        } else if (T == f64) {
            return glib.Variant.newDouble(contents);
        } else if (comptime isCString(T)) {
            return glib.Variant.newString(contents);
        } else if (T == *glib.Variant) {
            return glib.Variant.newVariant(contents);
        } else if (type_info == .array) {
            const child_type = glib.ext.VariantType.newFor(type_info.array.child);
            defer child_type.free();
            var children: [type_info.array.len]*glib.Variant = undefined;
            inline for (contents, &children) |item, *child| {
                child.* = newFrom(item);
            }
            return glib.Variant.newArray(child_type, &children, children.len);
        } else if (type_info == .pointer and type_info.pointer.size == .slice) {
            const child_type = glib.ext.VariantType.newFor(type_info.pointer.child);
            defer child_type.free();
            const children = alloc(*glib.Variant, contents.len);
            defer free(children);
            for (contents, children) |item, *child| {
                child.* = newFrom(item);
            }
            return glib.Variant.newArray(child_type, children.ptr, children.len);
        } else if (type_info == .optional) {
            const child_type = glib.ext.VariantType.newFor(type_info.optional.child);
            defer child_type.free();
            if (contents) |value| {
                const child = newFrom(value);
                return glib.Variant.newMaybe(child_type, child);
            } else {
                return glib.Variant.newMaybe(child_type, null);
            }
        } else if (type_info == .@"struct" and type_info.@"struct".is_tuple) {
            var children: [type_info.@"struct".fields.len]*glib.Variant = undefined;
            inline for (type_info.@"struct".fields, &children) |field, *child| {
                child.* = newFrom(@field(contents, field.name));
            }
            return glib.Variant.newTuple(&children, children.len);
        } else {
            @compileError("cannot construct variant from " ++ @typeName(T));
        }
    }

    test "newFrom(integer)" {
        try testVariantNewFrom(u8, 123, glib.Variant.getByte);
        try testVariantNewFrom(i16, -12345, glib.Variant.getInt16);
        try testVariantNewFrom(i32, -(1 << 24), glib.Variant.getInt32);
        try testVariantNewFrom(i64, -(1 << 48), glib.Variant.getInt64);
        try testVariantNewFrom(u16, 12345, glib.Variant.getUint16);
        try testVariantNewFrom(u32, 1 << 24, glib.Variant.getUint32);
        try testVariantNewFrom(u64, 1 << 48, glib.Variant.getUint64);
        try testVariantNewFrom(f64, 3.1415926, glib.Variant.getDouble);
    }

    test "newFrom(bool)" {
        const variant = glib.ext.Variant.newFrom(true);
        defer variant.unref();
        try std.testing.expectEqual(1, variant.getBoolean());
    }

    test "newFrom(string literal)" {
        const variant = glib.ext.Variant.newFrom("Hello, world!");
        defer variant.unref();
        var len: usize = undefined;
        const string = variant.getString(&len);
        try std.testing.expectEqualStrings("Hello, world!", string[0..len]);
    }

    test "newFrom([*:0]const u8)" {
        const str: [*:0]const u8 = "Hello, world!";
        const variant = glib.ext.Variant.newFrom(str);
        defer variant.unref();
        var len: usize = undefined;
        const string = variant.getString(&len);
        try std.testing.expectEqualStrings("Hello, world!", string[0..len]);
    }

    test "newFrom([:0]const u8)" {
        const str: [:0]const u8 = "Hello, world!";
        const variant = glib.ext.Variant.newFrom(str);
        defer variant.unref();
        var len: usize = undefined;
        const string = variant.getString(&len);
        try std.testing.expectEqualStrings("Hello, world!", string[0..len]);
    }

    test "newFrom([4]u16)" {
        const arr: [4]u16 = .{ 1, 2, 3, 4 };
        const variant = glib.ext.Variant.newFrom(arr);
        defer variant.unref();
        try std.testing.expectEqual(arr.len, variant.nChildren());
        for (arr, 0..) |item, i| {
            const child = variant.getChildValue(i);
            defer child.unref();
            try std.testing.expectEqual(item, child.getUint16());
        }
    }

    test "newFrom([]const u32)" {
        const slice: []const u32 = &.{ 1, 2, 3, 4, 5 };
        const variant = glib.ext.Variant.newFrom(slice);
        defer variant.unref();
        try std.testing.expectEqual(slice.len, variant.nChildren());
        for (slice, 0..) |item, i| {
            const child = variant.getChildValue(i);
            defer child.unref();
            try std.testing.expectEqual(item, child.getUint32());
        }
    }

    test "newFrom(?i16)" {
        {
            const opt: ?i16 = -12345;
            const variant = glib.ext.Variant.newFrom(opt);
            defer variant.unref();
            const maybe_child = variant.getMaybe();
            defer if (maybe_child) |child| child.unref();
            try std.testing.expect(maybe_child != null);
            try std.testing.expectEqual(-12345, maybe_child.?.getInt16());
        }

        {
            const opt: ?i16 = null;
            const variant = glib.ext.Variant.newFrom(opt);
            defer variant.unref();
            try std.testing.expectEqual(null, variant.getMaybe());
        }
    }

    test "newFrom(struct{u32, u64, i64})" {
        const tuple: struct { u32, u64, i64 } = .{ 1, 2, -3 };
        const variant = glib.ext.Variant.newFrom(tuple);
        defer variant.unref();
        try std.testing.expectEqual(tuple.len, variant.nChildren());
        {
            const child = variant.getChildValue(0);
            defer child.unref();
            try std.testing.expectEqual(tuple[0], child.getUint32());
        }
        {
            const child = variant.getChildValue(1);
            defer child.unref();
            try std.testing.expectEqual(tuple[1], child.getUint64());
        }
        {
            const child = variant.getChildValue(2);
            defer child.unref();
            try std.testing.expectEqual(tuple[2], child.getInt64());
        }
    }

    fn testVariantNewFrom(
        comptime T: type,
        data: T,
        getter: fn (*glib.Variant) callconv(.c) T,
    ) !void {
        const variant = glib.ext.Variant.newFrom(data);
        defer variant.unref();
        try std.testing.expectEqual(data, getter(variant));
    }
};

pub const VariantType = struct {
    /// Returns a new variant type corresponding to the given type.
    pub fn newFor(comptime T: type) *glib.VariantType {
        return glib.VariantType.new(stringFor(T));
    }

    /// Returns the variant type string corresponding to the given type.
    pub fn stringFor(comptime T: type) [:0]const u8 {
        const type_info = @typeInfo(T);
        if (T == bool) {
            return "b";
        } else if (T == u8) {
            return "y";
        } else if (T == i16) {
            return "n";
        } else if (T == u16) {
            return "q";
        } else if (T == i32) {
            return "i";
        } else if (T == u32) {
            return "u";
        } else if (T == i64) {
            return "x";
        } else if (T == u64) {
            return "t";
        } else if (T == f64) {
            return "d";
        } else if (comptime isCString(T)) {
            return "s";
        } else if (T == *glib.Variant) {
            return "v";
        } else if (type_info == .array) {
            return "a" ++ stringFor(type_info.array.child);
        } else if (type_info == .pointer and type_info.pointer.size == .slice) {
            return "a" ++ stringFor(type_info.pointer.child);
        } else if (type_info == .optional) {
            return "m" ++ stringFor(type_info.optional.child);
        } else if (type_info == .@"struct" and type_info.@"struct".is_tuple) {
            comptime var str: [:0]const u8 = "(";
            inline for (type_info.@"struct".fields) |field| {
                str = str ++ comptime stringFor(field.type);
            }
            return str ++ ")";
        } else {
            @compileError("cannot determine variant type for " ++ @typeName(T));
        }
    }
};

fn isCString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |info| switch (info.size) {
            .one => switch (@typeInfo(info.child)) {
                .array => |child| child.child == u8 and std.meta.sentinel(info.child) == 0,
                else => false,
            },
            .many, .slice => info.child == u8 and std.meta.sentinel(T) == 0,
            else => false,
        },
        else => false,
    };
}
