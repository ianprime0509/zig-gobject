const glib = @import("glib-2.0");
const std = @import("std");

pub const Bytes = struct {
    /// Returns a new `Bytes` copying the given slice.
    pub fn newFromSlice(bytes: []const u8) *glib.Bytes {
        // TODO: the const cast is only needed due to a mistranslation of the array type in new
        return glib.Bytes.new(@constCast(bytes.ptr), bytes.len);
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
        } else if (type_info == .Array) {
            const child_type = glib.ext.VariantType.newFor(type_info.Array.child);
            defer child_type.free();
            var children: [type_info.Array.len]*glib.Variant = undefined;
            inline for (contents, &children) |item, *child| {
                child.* = newFrom(item);
            }
            return glib.Variant.newArray(child_type, &children, children.len);
        } else if (type_info == .Pointer and type_info.Pointer.size == .Slice) {
            @compileError("TODO: slices should be implemented here");
        } else if (type_info == .Optional) {
            const child_type = glib.ext.VariantType.newFor(type_info.Optional.child);
            defer child_type.free();
            if (contents) |value| {
                const child = newFrom(value);
                return glib.Variant.newMaybe(child_type, child);
            } else {
                return glib.Variant.newMaybe(child_type, null);
            }
        } else if (type_info == .Struct and type_info.Struct.is_tuple) {
            var children: [type_info.Struct.fields.len]*glib.Variant = undefined;
            inline for (type_info.Struct.fields, &children) |field, *child| {
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
        } else if (type_info == .Array) {
            return "a" ++ stringFor(type_info.Array.child);
        } else if (type_info == .Pointer and type_info.Pointer.size == .Slice) {
            return "a" ++ stringFor(type_info.Pointer.child);
        } else if (type_info == .Optional) {
            return "m" ++ stringFor(type_info.Optional.child);
        } else if (type_info == .Struct and type_info.Struct.is_tuple) {
            comptime var str: [:0]const u8 = "(";
            inline for (type_info.Struct.fields) |field| {
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
        .Pointer => |info| switch (info.size) {
            .One => switch (@typeInfo(info.child)) {
                .Array => |child| child.child == u8 and std.meta.sentinel(info.child) == @as(u8, 0),
                else => false,
            },
            .Many => info.child == u8 and std.meta.sentinel(T) == @as(u8, 0),
            else => false,
        },
        else => false,
    };
}
