//! Compatibility wrappers for the latest tagged release of Zig.

const std = @import("std");
const expect = std.testing.expect;

/// https://github.com/ziglang/zig/pull/21225
pub const TypeInfo = if (type_has_new_fields) std.builtin.Type else TypeCompat;

const type_has_new_fields = @hasField(std.builtin.Type, "type");

pub fn typeInfo(comptime T: type) TypeInfo {
    if (type_has_new_fields) return @typeInfo(T);
    return switch (@typeInfo(T)) {
        inline else => |info, tag| @unionInit(TypeInfo, type_new_fields.get(@tagName(tag)).?, info),
    };
}

test typeInfo {
    const MyStruct = struct {
        a: u32,
        b: []const u8,
    };
    const type_info = typeInfo(MyStruct);
    try expect(type_info == .@"struct");
    try expect(type_info.@"struct".fields.len == 2);
    try expect(type_info.@"struct".fields[0].type == u32);
    try expect(type_info.@"struct".fields[1].type == []const u8);
}

pub fn Reify(comptime type_info: TypeInfo) type {
    if (type_has_new_fields) return @Type(type_info);
    return @Type(switch (type_info) {
        inline else => |info, tag| @unionInit(std.builtin.Type, type_old_fields.get(@tagName(tag)).?, info),
    });
}

test Reify {
    const MyU32 = Reify(.{ .int = .{
        .bits = 32,
        .signedness = .unsigned,
    } });
    const value: MyU32 = 123;
    try expect(@TypeOf(value) == u32);
}

const type_field_names: []const struct { [:0]const u8, [:0]const u8 } = &.{
    .{ "Type", "type" },
    .{ "Void", "void" },
    .{ "Bool", "bool" },
    .{ "NoReturn", "noreturn" },
    .{ "Int", "int" },
    .{ "Float", "float" },
    .{ "Pointer", "pointer" },
    .{ "Array", "array" },
    .{ "Struct", "struct" },
    .{ "ComptimeFloat", "comptime_float" },
    .{ "ComptimeInt", "comptime_int" },
    .{ "Undefined", "undefined" },
    .{ "Null", "null" },
    .{ "Optional", "optional" },
    .{ "ErrorUnion", "error_union" },
    .{ "ErrorSet", "error_set" },
    .{ "Enum", "enum" },
    .{ "Union", "union" },
    .{ "Fn", "fn" },
    .{ "Opaque", "opaque" },
    .{ "Frame", "frame" },
    .{ "AnyFrame", "anyframe" },
    .{ "Vector", "vector" },
    .{ "EnumLiteral", "enum_literal" },
};

const type_new_fields = std.StaticStringMap([:0]const u8).initComptime(type_field_names);
const type_old_fields = type_old_fields: {
    var mappings: [type_field_names.len]struct { [:0]const u8, [:0]const u8 } = undefined;
    for (type_field_names, &mappings) |old_to_new, *new_to_old| {
        new_to_old.* = .{ old_to_new[1], old_to_new[0] };
    }
    break :type_old_fields std.StaticStringMap([:0]const u8).initComptime(mappings);
};

const TypeCompat = TypeCompat: {
    var builtin_type = @typeInfo(std.builtin.Type).Union;
    var builtin_type_tag = @typeInfo(builtin_type.tag_type.?).Enum;

    var compat_type_tag_fields = builtin_type_tag.fields[0..builtin_type_tag.fields.len].*;
    for (&compat_type_tag_fields) |*field| {
        field.name = type_new_fields.get(field.name).?;
    }
    const TypeCompatTag = @Type(.{ .Enum = .{
        .tag_type = builtin_type_tag.tag_type,
        .fields = &compat_type_tag_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });

    var compat_type_fields = builtin_type.fields[0..builtin_type.fields.len].*;
    for (&compat_type_fields) |*field| {
        field.name = type_new_fields.get(field.name).?;
    }

    break :TypeCompat @Type(.{ .Union = .{
        .layout = .auto,
        .tag_type = TypeCompatTag,
        .fields = &compat_type_fields,
        .decls = &.{},
    } });
};
