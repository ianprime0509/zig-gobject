const glib = @import("glib2");
const std = @import("std");
const compat = @import("compat");

/// Creates a heap-allocated value of type `T` using `glib.malloc`. `T` must not
/// be zero-sized or aligned more than `std.c.max_align_t`.
pub fn create(comptime T: type) *T {
    if (@sizeOf(T) == 0) @compileError("zero-sized types not supported");
    if (@alignOf(T) > @alignOf(std.c.max_align_t)) @compileError("overaligned types not supported");
    return @ptrCast(@alignCast(glib.malloc(@sizeOf(T))));
}

/// Creates a heap-allocated copy of `value` using `glib.malloc`. `T` must not
/// be zero-sized or aligned more than `std.c.max_align_t`.
pub inline fn new(comptime T: type, value: T) *T {
    const new_value = create(T);
    new_value.* = value;
    return new_value;
}

/// Destroys a value created using `create`.
pub fn destroy(ptr: anytype) void {
    const type_info = compat.typeInfo(@TypeOf(ptr));
    if (type_info != .pointer or type_info.pointer.size != .One) @compileError("must be a single-item pointer");
    glib.freeSized(@ptrCast(ptr), @sizeOf(type_info.pointer.child));
}

/// Heap allocates a slice of `n` values of type `T` using `glib.mallocN`. `T`
/// must not be zero-sized or aligned more than `std.c.max_align_t`.
pub fn alloc(comptime T: type, n: usize) []T {
    if (@sizeOf(T) == 0) @compileError("zero-sized types not supported");
    if (@alignOf(T) > @alignOf(std.c.max_align_t)) @compileError("overaligned types not supported");
    const ptr: [*]T = @ptrCast(@alignCast(glib.mallocN(@sizeOf(T), n)));
    return ptr[0..n];
}

/// Frees a slice created using `alloc`.
pub fn free(ptr: anytype) void {
    const type_info = compat.typeInfo(@TypeOf(ptr));
    if (type_info != .pointer or type_info.pointer.size != .Slice) @compileError("must be a slice");
    glib.freeSized(@ptrCast(ptr.ptr), @sizeOf(type_info.pointer.child) * ptr.len);
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
};

pub const Variant = struct {
    /// Returns a new `Variant` with the given contents.
    ///
    /// This does not take ownership of the value (if applicable).
    pub fn newFrom(contents: anytype) *glib.Variant {
        const T = @TypeOf(contents);
        const type_info = compat.typeInfo(T);
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
        } else if (type_info == .pointer and type_info.pointer.size == .Slice) {
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
};

pub const VariantType = struct {
    /// Returns a new variant type corresponding to the given type.
    pub fn newFor(comptime T: type) *glib.VariantType {
        return glib.VariantType.new(stringFor(T));
    }

    /// Returns the variant type string corresponding to the given type.
    pub fn stringFor(comptime T: type) [:0]const u8 {
        const type_info = compat.typeInfo(T);
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
        } else if (type_info == .pointer and type_info.pointer.size == .Slice) {
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
    return switch (compat.typeInfo(T)) {
        .pointer => |info| switch (info.size) {
            .One => switch (compat.typeInfo(info.child)) {
                .array => |child| child.child == u8 and std.meta.sentinel(info.child) == 0,
                else => false,
            },
            .Many, .Slice => info.child == u8 and std.meta.sentinel(T) == 0,
            else => false,
        },
        else => false,
    };
}
