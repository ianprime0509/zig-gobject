const glib = @import("glib2");
const gobject = @import("gobject2");
const std = @import("std");

/// Fundamental types.
pub const types = struct {
    // Values taken from gtype.h.
    pub const invalid = makeFundamental(0);
    pub const none = makeFundamental(1);
    pub const interface = makeFundamental(2);
    pub const char = makeFundamental(3);
    pub const uchar = makeFundamental(4);
    pub const boolean = makeFundamental(5);
    pub const int = makeFundamental(6);
    pub const uint = makeFundamental(7);
    pub const long = makeFundamental(8);
    pub const ulong = makeFundamental(9);
    pub const int64 = makeFundamental(10);
    pub const uint64 = makeFundamental(11);
    pub const @"enum" = makeFundamental(12);
    pub const flags = makeFundamental(13);
    pub const float = makeFundamental(14);
    pub const double = makeFundamental(15);
    pub const string = makeFundamental(16);
    pub const pointer = makeFundamental(17);
    pub const boxed = makeFundamental(18);
    pub const param = makeFundamental(19);
    pub const object = makeFundamental(20);
    pub const variant = makeFundamental(21);

    /// A translation of the `G_TYPE_MAKE_FUNDAMENTAL` macro.
    pub fn makeFundamental(x: usize) gobject.Type {
        return x << gobject.TYPE_FUNDAMENTAL_SHIFT;
    }
};

/// Returns the GObject `Type` corresponding to the given type.
pub fn typeFor(comptime T: type) gobject.Type {
    // Types manually extracted from gtype.h since they don't seem to show up in GIR
    if (T == void) {
        return types.none;
    } else if (T == i8) {
        return types.char;
    } else if (T == u8) {
        return types.uchar;
    } else if (T == bool) {
        return types.boolean;
    } else if (T == c_int) {
        return types.int;
    } else if (T == c_uint) {
        return types.uint;
    } else if (T == c_long) {
        return types.long;
    } else if (T == c_ulong) {
        return types.ulong;
    } else if (T == i64) {
        return types.int64;
    } else if (T == u64) {
        return types.uint64;
    } else if (T == f32) {
        return types.float;
    } else if (T == f64) {
        return types.double;
    } else if (comptime isCString(T)) {
        return types.string;
    } else if (std.meta.hasFn(T, "getGObjectType")) {
        return T.getGObjectType();
    } else if (singlePointerChild(T)) |Child| {
        if (Child == gobject.ParamSpec) {
            return types.param;
        } else if (Child == glib.Variant) {
            return types.variant;
        } else if (std.meta.hasFn(Child, "getGObjectType")) {
            return Child.getGObjectType();
        } else {
            @compileError("unable to determine GObject type for " ++ @typeName(T));
        }
    } else {
        // Generic "pointer" types are intentionally not supported here because
        // they could easily be confusing for users defining custom types who
        // just forgot to define the getGObjectType function.
        @compileError("unable to determine GObject type for " ++ @typeName(T));
    }
}

/// Ensures the GObject type `T` is registered with the GObject type system and
/// initialized.
pub fn ensureType(comptime T: type) void {
    gobject.typeEnsure(T.getGObjectType());
}

pub fn DefineClassOptions(comptime Instance: type) type {
    return struct {
        /// The name of the type. The default is to use the base type name of
        /// `Instance`.
        name: ?[:0]const u8 = null,
        flags: gobject.TypeFlags = .{},
        baseInit: ?*const fn (*Instance.Class) callconv(.c) void = null,
        baseFinalize: ?*const fn (*Instance.Class) callconv(.c) void = null,
        classInit: ?*const fn (*Instance.Class) callconv(.c) void = null,
        classFinalize: ?*const fn (*Instance.Class) callconv(.c) void = null,
        instanceInit: ?*const fn (*Instance, *Instance.Class) callconv(.c) void = null,
        /// Interface implementations, created using `implement`.
        ///
        /// The interface types specified here must match the top-level
        /// `Implements` member of `Instance`, which is expected to be an array
        /// of all interface types implemented by `Instance`.
        implements: []const InterfaceImplementation = &.{},
        /// If non-null, will be set to the instance of the parent class when
        /// the class is initialized.
        parent_class: ?**Instance.Parent.Class = null,
        /// Metadata for private instance data. When the class is initialized,
        /// `offset` is updated to the offset of the private data relative to
        /// the instance.
        ///
        /// `impl_helpers.getPrivate` can be used to get this private data
        /// within the class implementation.
        private: ?struct {
            Type: type,
            offset: *c_int,
        } = null,
    };
}

/// Contains information required to implement an interface.
///
/// Users should generally not initialize this directly, but rather use
/// `implement` for greater type safety.
pub const InterfaceImplementation = struct {
    Iface: type,
    info: gobject.InterfaceInfo,
};

pub fn ImplementOptions(comptime Iface: type) type {
    return struct {
        init: ?*const fn (*Iface.Iface) callconv(.c) void = null,
        finalize: ?*const fn (*Iface.Iface) callconv(.c) void = null,
    };
}

/// Specifies an interface type to be implemented and the lifecycle functions to
/// do so.
pub fn implement(comptime Iface: type, comptime options: ImplementOptions(Iface)) InterfaceImplementation {
    return .{
        .Iface = Iface,
        .info = .{
            .f_interface_init = @ptrCast(options.init),
            .f_interface_finalize = @ptrCast(options.finalize),
            .f_interface_data = null,
        },
    };
}

/// Sets up a class type in the GObject type system, returning the associated
/// `getGObjectType` function.
///
/// The `Instance` parameter is the instance struct for the type. There are
/// several constraints on this type:
///
/// - It must be an `extern struct`, and the first member must be of type `Parent`
/// - It must have a public declaration named `Parent` referring to the parent type
///   (creating new fundamental types is not currently supported)
/// - `Parent` must be a valid GObject type
/// - It must have a public declaration named `Class` referring to the class struct
/// - `Class` must be an `extern struct`, and the first member must be of type
///   `Parent.Class`
/// - `Class` must have a public declaration named `Instance` referring to the
///   instance struct
///
/// Lifecycle methods and private data can be defined in the `options` struct.
pub fn defineClass(
    comptime Instance: type,
    comptime options: DefineClassOptions(Instance),
) fn () callconv(.c) gobject.Type {
    const instance_info = @typeInfo(Instance);
    if (instance_info != .@"struct" or instance_info.@"struct".layout != .@"extern") {
        @compileError("an instance type must be an extern struct");
    }

    if (!@hasDecl(Instance, "Parent")) {
        @compileError("a class type must have a declaration named Parent pointing to the parent type");
    }
    const parent_info = @typeInfo(Instance.Parent);
    if (parent_info != .@"struct" or parent_info.@"struct".layout != .@"extern" or !@hasDecl(Instance.Parent, "getGObjectType")) {
        @compileError("the defined parent type " ++ @typeName(Instance.Parent) ++ " does not appear to be a GObject class type");
    }
    if (instance_info.@"struct".fields.len == 0 or instance_info.@"struct".fields[0].type != Instance.Parent) {
        @compileError("the first field of the instance struct must have type " ++ @typeName(Instance.Parent));
    }

    if (!@hasDecl(Instance, "Class")) {
        @compileError("a class type must have a member named Class pointing to the class record");
    }
    const class_info = @typeInfo(Instance.Class);
    if (class_info != .@"struct" or class_info.@"struct".layout != .@"extern") {
        @compileError("a class type must be an extern struct");
    }
    if (!@hasDecl(Instance.Class, "Instance") or Instance.Class.Instance != Instance) {
        @compileError("a class type must have a declaration named Instance pointing to the instance type");
    }
    if (class_info.@"struct".fields.len == 0 or class_info.@"struct".fields[0].type != Instance.Parent.Class) {
        @compileError("the first field of the class struct must have type " ++ @typeName(Instance.Parent.Class));
    }

    return struct {
        var registered_type: gobject.Type = 0;

        pub fn getGObjectType() callconv(.c) gobject.Type {
            if (glib.Once.initEnter(&registered_type) != 0) {
                const classInitFunc = struct {
                    fn classInit(class: *Instance.Class) callconv(.c) void {
                        if (options.parent_class) |parent_class| {
                            const parent = gobject.TypeClass.peekParent(as(gobject.TypeClass, class));
                            parent_class.* = @ptrCast(@alignCast(parent));
                        }
                        if (options.private) |private| {
                            gobject.TypeClass.adjustPrivateOffset(class, private.offset);
                        }
                        if (options.classInit) |userClassInit| {
                            userClassInit(class);
                        }
                    }
                }.classInit;
                const info: gobject.TypeInfo = .{
                    .f_class_size = @sizeOf(Instance.Class),
                    .f_base_init = @ptrCast(options.baseInit),
                    .f_base_finalize = @ptrCast(options.baseFinalize),
                    .f_class_init = @ptrCast(&classInitFunc),
                    .f_class_finalize = @ptrCast(options.classFinalize),
                    .f_class_data = null,
                    .f_instance_size = @sizeOf(Instance),
                    .f_n_preallocs = 0,
                    .f_instance_init = @ptrCast(options.instanceInit),
                    .f_value_table = null,
                };

                const type_id = gobject.typeRegisterStatic(
                    Instance.Parent.getGObjectType(),
                    options.name orelse deriveTypeName(Instance),
                    &info,
                    options.flags,
                );

                if (options.private) |private| {
                    private.offset.* = gobject.typeAddInstancePrivate(type_id, @sizeOf(private.Type));
                }

                {
                    const Implements = if (@hasDecl(Instance, "Implements")) Instance.Implements else [_]type{};
                    comptime var found = [_]bool{false} ** Implements.len;
                    inline for (options.implements) |implementation| {
                        inline for (Implements, &found) |Iface, *found_match| {
                            if (implementation.Iface == Iface) {
                                if (found_match.*) @compileError("duplicate implementation of " ++ @typeName(Iface));
                                gobject.typeAddInterfaceStatic(type_id, implementation.Iface.getGObjectType(), &implementation.info);
                                found_match.* = true;
                                break;
                            }
                        }
                    }
                    inline for (Implements, found) |Iface, found_match| {
                        if (!found_match) @compileError("missing implementation of " ++ @typeName(Iface));
                    }
                }

                glib.Once.initLeave(&registered_type, type_id);
            }
            return registered_type;
        }
    }.getGObjectType;
}

test defineClass {
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

        fn init(self: *Self, _: *Self.Class) callconv(.c) void {
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
    try std.testing.expectEqual(123, obj.getSomeValue());
    try std.testing.expect(gobject.ext.isA(obj, gobject.Object));
    try std.testing.expect(gobject.ext.cast(gobject.Object, obj) != null);
}

pub fn DefineBoxedOptions(comptime T: type) type {
    return struct {
        /// The name of the type. The default is to use the base type name of
        /// `Instance`.
        name: ?[:0]const u8 = null,
        /// Functions describing how to copy and free instances of the type. If
        /// these are not provided, the default is to use `glib.ext.create` and
        /// `glib.ext.destroy` to manage memory.
        funcs: ?struct {
            copy: *const fn (*T) *T,
            free: *const fn (*T) void,
        } = null,
    };
}

/// Sets up a boxed type in the GObject type system, returning the associated
/// `getGObjectType` function.
pub fn defineBoxed(
    comptime T: type,
    comptime options: DefineBoxedOptions(T),
) fn () callconv(.c) gobject.Type {
    const funcs = options.funcs orelse .{
        .copy = &struct {
            fn copy(value: *T) callconv(.c) *T {
                const new_value = glib.ext.create(T);
                new_value.* = value.*;
                return new_value;
            }
        }.copy,
        .free = &struct {
            fn free(value: *T) callconv(.c) void {
                glib.ext.destroy(value);
            }
        }.free,
    };

    return struct {
        var registered_type: gobject.Type = 0;

        pub fn getGObjectType() callconv(.c) gobject.Type {
            if (glib.Once.initEnter(&registered_type) != 0) {
                const type_id = gobject.boxedTypeRegisterStatic(
                    options.name orelse deriveTypeName(T),
                    @ptrCast(funcs.copy),
                    @ptrCast(funcs.free),
                );
                glib.Once.initLeave(&registered_type, type_id);
            }
            return registered_type;
        }
    }.getGObjectType;
}

test defineBoxed {
    const MyBoxed = struct {
        a: u32,
        b: u32,

        pub const getGObjectType = gobject.ext.defineBoxed(@This(), .{});
    };

    const value1: *const MyBoxed = &.{ .a = 123, .b = 456 };
    const value2: *MyBoxed = @ptrCast(@alignCast(gobject.boxedCopy(MyBoxed.getGObjectType(), value1)));
    defer gobject.boxedFree(MyBoxed.getGObjectType(), value2);
    try std.testing.expectEqual(123, value2.a);
    try std.testing.expectEqual(456, value2.b);
}

pub const DefineEnumOptions = struct {
    /// The name of the type. The default is to use the base type name of the
    /// enum.
    name: ?[:0]const u8 = null,
};

/// Sets up an enum type in the GObject type system, returning the associated
/// `getGObjectType` function.
///
/// Enum types must have a tag type of `c_int`.
pub fn defineEnum(
    comptime Enum: type,
    comptime options: DefineEnumOptions,
) fn () callconv(.c) gobject.Type {
    const enum_info = @typeInfo(Enum);
    if (enum_info != .@"enum" or enum_info.@"enum".tag_type != c_int) {
        @compileError("an enum type must have a tag type of c_int");
    }
    if (!enum_info.@"enum".is_exhaustive) {
        @compileError("an enum type must be exhaustive");
    }

    const n_values = enum_info.@"enum".fields.len;
    var enum_values: [n_values + 1]gobject.EnumValue = undefined;
    for (enum_info.@"enum".fields, enum_values[0..n_values]) |field, *value| {
        value.* = .{
            .f_value = field.value,
            .f_value_name = field.name,
            .f_value_nick = field.name,
        };
    }
    enum_values[n_values] = .{
        .f_value = 0,
        .f_value_name = null,
        .f_value_nick = null,
    };
    const const_enum_values = enum_values;

    return struct {
        var registered_type: gobject.Type = 0;

        pub fn getGObjectType() callconv(.c) gobject.Type {
            if (glib.Once.initEnter(&registered_type) != 0) {
                const type_id = gobject.enumRegisterStatic(
                    options.name orelse deriveTypeName(Enum),
                    &const_enum_values,
                );
                glib.Once.initLeave(&registered_type, type_id);
            }
            return registered_type;
        }
    }.getGObjectType;
}

test defineEnum {
    const MyEnum = enum(c_int) {
        one = 1,
        two = 2,
        three = 3,

        pub const getGObjectType = gobject.ext.defineEnum(@This(), .{});
    };

    const enum_type_class: *gobject.EnumClass = @ptrCast(gobject.TypeClass.ref(MyEnum.getGObjectType()));
    try std.testing.expectEqual(1, enum_type_class.f_minimum);
    try std.testing.expectEqual(3, enum_type_class.f_maximum);
    try std.testing.expectEqual(3, enum_type_class.f_n_values);
}

pub const DefineFlagsOptions = struct {
    /// The name of the type. The default is to use the base type name of the
    /// struct.
    name: ?[:0]const u8 = null,
};

/// Sets up a flags type in the GObject type system, returning the associated
/// `getGObjectType` function.
///
/// Flags types must be packed structs with a backing integer type of `c_uint`.
/// Fields inside the type whose names begin with `_` are interpreted as padding
/// and are not included as actual values in the registered flags type.
pub fn defineFlags(
    comptime Flags: type,
    comptime options: DefineFlagsOptions,
) fn () callconv(.c) gobject.Type {
    const flags_info = @typeInfo(Flags);
    if (flags_info != .@"struct" or flags_info.@"struct".layout != .@"packed" or flags_info.@"struct".backing_integer != c_uint) {
        @compileError("a flags type must have a backing integer type of c_uint");
    }

    comptime var n_values = 0;
    for (flags_info.@"struct".fields) |field| {
        if (!std.mem.startsWith(u8, field.name, "_")) {
            if (@bitSizeOf(field.type) != 1) {
                @compileError("non-padding flags field " ++ field.name ++ " must be 1 bit");
            }
            n_values += 1;
        }
    }
    comptime var flags_values: [n_values + 1]gobject.FlagsValue = undefined;
    var current_value = 0;
    for (flags_info.@"struct".fields) |field| {
        if (!std.mem.startsWith(u8, field.name, "_")) {
            flags_values[current_value] = .{
                .f_value = 1 << @bitOffsetOf(Flags, field.name),
                .f_value_name = field.name,
                .f_value_nick = field.name,
            };
            current_value += 1;
        }
    }
    flags_values[n_values] = .{
        .f_value = 0,
        .f_value_name = null,
        .f_value_nick = null,
    };
    const const_flags_values = flags_values;

    return struct {
        var registered_type: gobject.Type = 0;

        pub fn getGObjectType() callconv(.c) gobject.Type {
            if (glib.Once.initEnter(&registered_type) != 0) {
                const type_id = gobject.flagsRegisterStatic(
                    options.name orelse deriveTypeName(Flags),
                    &const_flags_values,
                );
                glib.Once.initLeave(&registered_type, type_id);
            }
            return registered_type;
        }
    }.getGObjectType;
}

test defineFlags {
    const MyFlags = packed struct(c_uint) {
        one: bool = false,
        two: i1 = -1,
        _padding0: u2 = 0,
        three: u1 = 1,
        _padding1: @Type(.{ .int = .{
            .signedness = .unsigned,
            .bits = @bitSizeOf(c_uint) - 5,
        } }) = 0,

        pub const getGObjectType = gobject.ext.defineFlags(@This(), .{});
    };

    const flags_type_class: *gobject.FlagsClass = @ptrCast(gobject.TypeClass.ref(MyFlags.getGObjectType()));
    try std.testing.expectEqual(0b10011, flags_type_class.f_mask);
    try std.testing.expectEqual(3, flags_type_class.f_n_values);
}

fn deriveTypeName(comptime T: type) [:0]const u8 {
    const name = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, name, '.')) |last_dot|
        name[last_dot + 1 ..]
    else
        name;
}

pub fn Accessor(comptime Owner: type, comptime Data: type) type {
    return struct {
        getter: ?*const fn (*Owner) Data = null,
        setter: ?*const fn (*Owner, Data) void = null,
    };
}

fn FieldType(comptime T: type, comptime name: []const u8) type {
    return for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) break field.type;
    } else @compileError("no field named " ++ name ++ " in " ++ @typeName(T));
}

/// Returns an `Accessor` which gets and sets a field `name` of `Owner`.
pub fn fieldAccessor(comptime Owner: type, comptime name: []const u8) Accessor(Owner, FieldType(Owner, name)) {
    return .{
        .getter = &struct {
            fn get(object: *Owner) FieldType(Owner, name) {
                return @field(object, name);
            }
        }.get,
        .setter = &struct {
            fn set(object: *Owner, value: FieldType(Owner, name)) void {
                @field(object, name) = value;
            }
        }.set,
    };
}

/// Returns an `Accessor` which gets and sets a private field `name` of `Owner`.
///
/// The private struct type, `Private`, and a pointer to its offset, `private_offset`,
/// must be provided to specify how to access the private data. The value pointed to
/// by `private_offset` must be initialized by the time the returned accessor is used.
pub fn privateFieldAccessor(
    comptime Owner: type,
    comptime Private: type,
    comptime private_offset: *const c_int,
    comptime name: []const u8,
) Accessor(Owner, FieldType(Private, name)) {
    return .{
        .getter = &struct {
            fn get(object: *Owner) FieldType(Private, name) {
                return @field(impl_helpers.getPrivate(object, Private, private_offset.*), name);
            }
        }.get,
        .setter = &struct {
            fn set(object: *Owner, value: FieldType(Private, name)) void {
                @field(impl_helpers.getPrivate(object, Private, private_offset.*), name) = value;
            }
        }.set,
    };
}

pub fn DefinePropertyOptions(comptime Owner: type, comptime Data: type) type {
    if (Data == bool) {
        return struct {
            nick: ?[:0]const u8 = null,
            blurb: ?[:0]const u8 = null,
            default: bool,
            accessor: Accessor(Owner, bool),
            construct: bool = false,
            construct_only: bool = false,
            lax_validation: bool = false,
            explicit_notify: bool = false,
            deprecated: bool = false,
        };
    } else if (Data == i8 or Data == u8 or
        Data == c_int or Data == c_uint or
        Data == c_long or Data == c_ulong or
        Data == i64 or Data == u64 or
        Data == f32 or Data == f64)
    {
        return struct {
            nick: ?[:0]const u8 = null,
            blurb: ?[:0]const u8 = null,
            minimum: Data,
            maximum: Data,
            default: Data,
            accessor: Accessor(Owner, Data),
            construct: bool = false,
            construct_only: bool = false,
            lax_validation: bool = false,
            explicit_notify: bool = false,
            deprecated: bool = false,
        };
    } else if (Data == ?[:0]const u8) {
        return struct {
            nick: ?[:0]const u8 = null,
            blurb: ?[:0]const u8 = null,
            default: ?[:0]const u8,
            accessor: Accessor(Owner, ?[:0]const u8),
            construct: bool = false,
            construct_only: bool = false,
            lax_validation: bool = false,
            explicit_notify: bool = false,
            deprecated: bool = false,
        };
    } else if (std.meta.hasFn(Data, "getGObjectType")) {
        return struct {
            nick: ?[:0]const u8 = null,
            blurb: ?[:0]const u8 = null,
            default: Data,
            accessor: Accessor(Owner, Data),
            construct: bool = false,
            construct_only: bool = false,
            lax_validation: bool = false,
            explicit_notify: bool = false,
            deprecated: bool = false,
        };
    } else if (singlePointerChild(Data)) |Child| {
        if (std.meta.hasFn(Child, "getGObjectType")) {
            return struct {
                nick: ?[:0]const u8 = null,
                blurb: ?[:0]const u8 = null,
                default: Data,
                accessor: Accessor(Owner, Data),
                construct: bool = false,
                construct_only: bool = false,
                lax_validation: bool = false,
                explicit_notify: bool = false,
                deprecated: bool = false,
            };
        } else {
            @compileError("cannot define property of type " ++ @typeName(Data));
        }
    } else {
        @compileError("cannot define property of type " ++ @typeName(Data));
    }
}

/// Sets up a property definition, returning a type with various helpers related
/// to the property.
pub fn defineProperty(
    comptime name: [:0]const u8,
    comptime Owner: type,
    comptime Data: type,
    comptime options: DefinePropertyOptions(Owner, Data),
) type {
    return struct {
        /// The `gobject.ParamSpec` of the property. Initialized once the
        /// property is registered.
        pub var param_spec: *gobject.ParamSpec = undefined;

        /// Registers the property.
        ///
        /// This is a lower-level function which should generally not be used
        /// directly. Users should generally call `registerProperties` instead,
        /// which handles registration of all a class's properties at once,
        /// along with configuring behavior for
        /// `gobject.Object.virtual_methods.get_property` and
        /// `gobject.Object.virtual_methods.set_property`.
        pub fn register(class: *Owner.Class, id: c_uint) void {
            param_spec = newParamSpec();
            gobject.Object.Class.installProperty(as(gobject.Object.Class, class), id, param_spec);
        }

        /// Gets the value of the property from `object` and stores it in
        /// `value`.
        pub fn get(object: *Owner, value: *gobject.Value) void {
            if (options.accessor.getter) |getter| {
                Value.set(value, getter(object));
            }
        }

        /// Sets the value of the property on `object` from `value`.
        pub fn set(object: *Owner, value: *const gobject.Value) void {
            if (options.accessor.setter) |setter| {
                setter(object, Value.get(value, Data));
            }
        }

        fn newParamSpec() *gobject.ParamSpec {
            const flags: gobject.ParamFlags = .{
                .readable = options.accessor.getter != null,
                .writable = options.accessor.setter != null,
                .construct = options.construct,
                .construct_only = options.construct_only,
                .lax_validation = options.lax_validation,
                .explicit_notify = options.explicit_notify,
                .deprecated = options.deprecated,
                // Since the name and options are comptime, we can set these flags
                // unconditionally.
                .static_name = true,
                .static_nick = true,
                .static_blurb = true,
            };
            if (Data == i8) {
                return gobject.paramSpecChar(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == u8) {
                return gobject.paramSpecUchar(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == bool) {
                return gobject.paramSpecBoolean(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    @intFromBool(options.default),
                    flags,
                );
            } else if (Data == c_int) {
                return gobject.paramSpecInt(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == c_uint) {
                return gobject.paramSpecUint(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == c_long) {
                return gobject.paramSpecLong(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == c_ulong) {
                return gobject.paramSpecUlong(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == i64) {
                return gobject.paramSpecInt64(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == u64) {
                return gobject.paramSpecUint64(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == f32) {
                return gobject.paramSpecFloat(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == f64) {
                return gobject.paramSpecDouble(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.minimum,
                    options.maximum,
                    options.default,
                    flags,
                );
            } else if (Data == ?[:0]const u8) {
                return gobject.paramSpecString(
                    name,
                    options.nick orelse null,
                    options.blurb orelse null,
                    options.default orelse null,
                    flags,
                );
            } else if (std.meta.hasFn(Data, "getGObjectType")) {
                return switch (@typeInfo(Data)) {
                    .@"enum" => gobject.paramSpecEnum(
                        name,
                        options.nick orelse null,
                        options.blurb orelse null,
                        Data.getGObjectType(),
                        @intFromEnum(options.default),
                        flags,
                    ),
                    .@"struct" => gobject.paramSpecFlags(
                        name,
                        options.nick orelse null,
                        options.blurb orelse null,
                        Data.getGObjectType(),
                        @bitCast(options.default),
                        flags,
                    ),
                    else => @compileError("unrecognized GObject type " ++ @typeName(Data)),
                };
            } else if (singlePointerChild(Data)) |Child| {
                if (std.meta.hasFn(Child, "getGObjectType")) {
                    const g_type = Child.getGObjectType();
                    if (isObject(Child)) {
                        return gobject.paramSpecObject(
                            name,
                            options.nick orelse null,
                            options.blurb orelse null,
                            g_type,
                            flags,
                        );
                    } else {
                        return gobject.paramSpecBoxed(
                            name,
                            options.nick orelse null,
                            options.blurb orelse null,
                            g_type,
                            flags,
                        );
                    }
                }
            } else {
                // New property data types must first be defined in
                // DefinePropertyOptions and then added here.
            }
        }
    };
}

/// Registers all properties of `class` and sets up virtual method
/// implementations for `gobject.Object.virtual_methods.get_property` and
/// `gobject.Object.virtual_methods.set_property`.
///
/// The properties passed in `properties` should be the structs returned by
/// `defineProperty`.
pub fn registerProperties(class: anytype, properties: []const type) void {
    const Instance = @typeInfo(@TypeOf(class)).pointer.child.Instance;
    gobject.Object.virtual_methods.get_property.implement(class, struct {
        fn getProperty(object: *Instance, id: c_uint, value: *gobject.Value, _: *gobject.ParamSpec) callconv(.c) void {
            inline for (properties, 1..) |property, i| {
                if (i == id) {
                    property.get(object, value);
                }
            }
        }
    }.getProperty);
    gobject.Object.virtual_methods.set_property.implement(class, struct {
        fn setProperty(object: *Instance, id: c_uint, value: *const gobject.Value, _: *gobject.ParamSpec) callconv(.c) void {
            inline for (properties, 1..) |property, i| {
                if (i == id) {
                    property.set(object, value);
                }
            }
        }
    }.setProperty);
    inline for (properties, 1..) |property, i| {
        property.register(class, i);
    }
}

pub fn SignalHandler(comptime Itype: type, comptime param_types: []const type, comptime DataType: type, comptime ReturnType: type) type {
    return *const @Type(.{ .@"fn" = .{
        .calling_convention = .C,
        .is_generic = false,
        .is_var_args = false,
        .return_type = ReturnType,
        .params = params: {
            var params: [param_types.len + 2]std.builtin.Type.Fn.Param = undefined;
            params[0] = .{ .is_generic = false, .is_noalias = false, .type = *Itype };
            for (param_types, params[1 .. params.len - 1]) |ParamType, *type_param| {
                type_param.* = .{ .is_generic = false, .is_noalias = false, .type = ParamType };
            }
            params[params.len - 1] = .{ .is_generic = false, .is_noalias = false, .type = DataType };
            break :params &params;
        },
    } });
}

pub const RegisterSignalOptions = struct {
    flags: gobject.SignalFlags = .{},
    class_closure: ?*gobject.Closure = null,
    accumulator: ?gobject.SignalAccumulator = null,
    accu_data: ?*anyopaque = null,
    c_marshaller: ?gobject.SignalCMarshaller = null,
};

pub fn ConnectSignalOptions(comptime Data: type) type {
    return struct {
        detail: ?[:0]const u8 = null,
        after: bool = false,
        destroyData: ?*const fn (Data) callconv(.c) void = null,
    };
}

/// Sets up a signal definition, returning a type with various helpers
/// related to the signal.
pub fn defineSignal(
    comptime name: [:0]const u8,
    comptime Itype: type,
    comptime param_types: []const type,
    comptime ReturnType: type,
) type {
    const EmitParams = @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields: {
            var fields: [param_types.len]std.builtin.Type.StructField = undefined;
            for (param_types, &fields, 0..) |ParamType, *field, i| {
                field.* = .{
                    .name = std.fmt.comptimePrint("{}", .{i}),
                    .type = ParamType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(ParamType),
                };
            }
            break :fields &fields;
        },
        .decls = &.{},
        .is_tuple = true,
    } });

    return struct {
        /// The ID of the signal. Initialized once the signal is registered.
        pub var id: c_uint = undefined;

        /// Registers the signal.
        ///
        /// This should generally be called during the class initializer of the
        /// target type.
        pub fn register(options: RegisterSignalOptions) void {
            var param_gtypes: [param_types.len]gobject.Type = undefined;
            inline for (param_types, &param_gtypes) |ParamType, *param_gtype| {
                param_gtype.* = gobject.ext.typeFor(ParamType);
            }
            id = gobject.signalNewv(
                name,
                gobject.ext.typeFor(*Itype),
                options.flags,
                options.class_closure,
                options.accumulator,
                options.accu_data,
                options.c_marshaller,
                gobject.ext.typeFor(ReturnType),
                param_gtypes.len,
                &param_gtypes,
            );
        }

        /// Emits the signal on an instance.
        pub fn emit(target: *Itype, detail: ?[:0]const u8, params: EmitParams, return_value: ?*ReturnType) void {
            var emit_params: [param_types.len + 1]gobject.Value = undefined;
            emit_params[0] = gobject.ext.Value.newFrom(target);
            inline for (params, emit_params[1..]) |param, *emit_param| {
                emit_param.* = gobject.ext.Value.newFrom(param);
            }
            defer for (&emit_params) |*emit_param| emit_param.unset();
            const detail_quark = if (detail) |detail_str| glib.quarkFromString(detail_str) else 0;
            var raw_return_value: gobject.Value = gobject.ext.Value.zero;
            gobject.signalEmitv(&emit_params, id, detail_quark, &raw_return_value);
            if (ReturnType != void) {
                if (return_value) |return_value_location| {
                    return_value_location.* = gobject.ext.Value.get(&raw_return_value, ReturnType);
                }
            }
        }

        /// Connects a handler to the signal on an instance.
        pub fn connect(
            target: anytype,
            comptime Data: type,
            callback: SignalHandler(@typeInfo(@TypeOf(target)).pointer.child, param_types, Data, ReturnType),
            data: Data,
            options: ConnectSignalOptions(Data),
        ) c_ulong {
            return gobject.signalConnectClosureById(
                @ptrCast(@alignCast(as(Itype, target))),
                gobject.signalLookup(name, Itype.getGObjectType()),
                glib.quarkFromString(options.detail orelse null),
                gobject.CClosure.new(@ptrCast(callback), data, @ptrCast(options.destroyData)),
                @intFromBool(options.after),
            );
        }
    };
}

/// Implementation helpers not meant to be used outside implementations of
/// new classes.
pub const impl_helpers = struct {
    /// Returns a pointer to the private data struct of the given instance.
    ///
    /// ```zig
    /// fn private(self: *Self) *Private {
    ///     return gobject.getPrivate(self, Private, Private.offset);
    /// }
    /// ```
    pub fn getPrivate(self: *anyopaque, comptime Private: type, offset: c_int) *Private {
        return @ptrFromInt(@intFromPtr(self) +% @as(usize, @bitCast(@as(isize, offset))));
    }
};

/// Safely casts a type or type class instance to an instance of `T`,
/// emitting a compilation error if the safety of the cast cannot be
/// guaranteed.
pub inline fn as(comptime T: type, self: anytype) *T {
    const self_info = @typeInfo(@TypeOf(self));
    if (self_info != .pointer or self_info.pointer.size != .one) {
        @compileError("cannot cast a non-pointer type");
    }
    const Self = self_info.pointer.child;

    if (isAssignableFrom(T, Self)) {
        return @ptrCast(@alignCast(self));
    }

    @compileError(@typeName(Self) ++ " is not guaranteed to be assignable to " ++ @typeName(T));
}

/// Returns whether `Dest` is assignable from `Src`, that is, if it is
/// guaranteed to be safe to cast an instance of `Src` to `Dest`.
pub inline fn isAssignableFrom(comptime Dest: type, comptime Src: type) bool {
    if (Src == Dest) return true;

    if (@hasDecl(Src, "Instance")) {
        // This is a class or interface struct type.
        if (@hasDecl(Src.Instance, "Parent")) {
            if (@hasDecl(Src.Instance.Parent, "Class")) {
                return isAssignableFrom(Dest, Src.Instance.Parent.Class);
            } else if (@hasDecl(Src.Instance.Parent, "Iface")) {
                return isAssignableFrom(Dest, Src.Instance.Parent.Iface);
            } else if (Src.Instance.Parent == gobject.TypeInstance) {
                return Dest == gobject.TypeClass;
            }
        }
        return false;
    }

    if (@hasDecl(Src, "Implements")) {
        inline for (Src.Implements) |Implements| {
            if (isAssignableFrom(Dest, Implements)) return true;
        }
    }

    if (@hasDecl(Src, "Prerequisites")) {
        inline for (Src.Prerequisites) |Prerequisite| {
            if (isAssignableFrom(Dest, Prerequisite)) return true;
        }
    }

    if (@hasDecl(Src, "Parent")) {
        return isAssignableFrom(Dest, Src.Parent);
    }

    return false;
}

test isAssignableFrom {
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.Object));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.TypeInstance, gobject.Object));
    try std.testing.expect(!gobject.ext.isAssignableFrom(gobject.Object, gobject.TypeInstance));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.InitiallyUnowned));
    try std.testing.expect(!gobject.ext.isAssignableFrom(gobject.InitiallyUnowned, gobject.Object));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.TypeInstance, gobject.InitiallyUnowned));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.TypePlugin));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object, gobject.TypeModule));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.InitiallyUnowned.Class));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.TypeClass, gobject.InitiallyUnowned.Class));
    try std.testing.expect(!gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.TypeClass));
    try std.testing.expect(gobject.ext.isAssignableFrom(gobject.Object.Class, gobject.InitiallyUnowned.Class));
    try std.testing.expect(!gobject.ext.isAssignableFrom(gobject.InitiallyUnowned.Class, gobject.Object.Class));
}

/// Casts a type instance to another type, or returns null if it is not an instance of the type.
pub fn cast(comptime T: type, self: anytype) ?*T {
    return if (isA(self, T)) @ptrCast(@alignCast(self)) else null;
}

/// Returns whether a type instance is an instance of the given type or some sub-type.
pub fn isA(self: anytype, comptime T: type) bool {
    return gobject.typeCheckInstanceIsA(as(gobject.TypeInstance, self), typeFor(*T)) != 0;
}

/// Creates a new instance of an object type with the given properties.
pub fn newInstance(comptime T: type, properties: anytype) *T {
    const typeInfo = @typeInfo(@TypeOf(properties)).@"struct";
    const n_props = typeInfo.fields.len;
    var names: [n_props][*:0]const u8 = undefined;
    var values: [n_props]gobject.Value = undefined;
    inline for (typeInfo.fields, 0..) |field, i| {
        names[i] = field.name ++ "\x00";
        values[i] = gobject.ext.Value.newFrom(@field(properties, field.name));
    }
    defer for (&values) |*value| value.unset();
    const instance = gobject.Object.newWithProperties(T.getGObjectType(), n_props, &names, &values);
    return @ptrCast(@alignCast(instance));
}

pub const Value = struct {
    /// The zero value for a `Value`. Values must not be `undefined` when
    /// calling `init` or any other function; they must be initialized to zero
    /// before use.
    pub const zero = std.mem.zeroes(gobject.Value);

    /// Returns a new `Value` intended to hold data of the given type.
    pub fn new(comptime T: type) gobject.Value {
        var value = zero;
        init(&value, T);
        return value;
    }

    /// Returns a new `Value` with the given contents.
    ///
    /// This does not take ownership of the value (if applicable).
    pub fn newFrom(contents: anytype) gobject.Value {
        var value: gobject.Value = new(@TypeOf(contents));
        set(&value, contents);
        return value;
    }

    /// Initializes `value` to store values of type `T`.
    pub fn init(value: *gobject.Value, comptime T: type) void {
        if (T == i8) {
            _ = value.init(types.char);
        } else if (T == u8) {
            _ = value.init(types.uchar);
        } else if (T == bool) {
            _ = value.init(types.boolean);
        } else if (T == c_int) {
            _ = value.init(types.int);
        } else if (T == c_uint) {
            _ = value.init(types.uint);
        } else if (T == c_long) {
            _ = value.init(types.long);
        } else if (T == c_ulong) {
            _ = value.init(types.ulong);
        } else if (T == i64) {
            _ = value.init(types.int64);
        } else if (T == u64) {
            _ = value.init(types.uint64);
        } else if (T == f32) {
            _ = value.init(types.float);
        } else if (T == f64) {
            _ = value.init(types.double);
        } else if (isCString(T)) {
            _ = value.init(types.string);
        } else if (std.meta.hasFn(T, "getGObjectType")) {
            _ = value.init(T.getGObjectType());
        } else if (singlePointerChild(T)) |Child| {
            if (Child == gobject.ParamSpec) {
                _ = value.init(types.param);
            } else if (Child == glib.Variant) {
                _ = value.init(types.variant);
            } else if (std.meta.hasFn(Child, "getGObjectType")) {
                _ = value.init(Child.getGObjectType());
            } else {
                @compileError("cannot initialize Value to store " ++ @typeName(T));
            }
        } else {
            @compileError("cannot initialize Value to store " ++ @typeName(T));
        }
    }

    /// Extracts a value of the given type.
    ///
    /// This does not return an owned value (if applicable): the caller must
    /// copy/ref/etc. the value if needed beyond the lifetime of the container.
    pub fn get(value: *const gobject.Value, comptime T: type) T {
        if (T == i8) {
            return value.getSchar();
        } else if (T == u8) {
            return value.getUchar();
        } else if (T == bool) {
            return value.getBoolean() != 0;
        } else if (T == c_int) {
            return value.getInt();
        } else if (T == c_uint) {
            return value.getUint();
        } else if (T == c_long) {
            return value.getLong();
        } else if (T == c_ulong) {
            return value.getUlong();
        } else if (T == i64) {
            return value.getInt64();
        } else if (T == u64) {
            return value.getUint64();
        } else if (T == f32) {
            return value.getFloat();
        } else if (T == f64) {
            return value.getDouble();
        } else if (isCString(T)) {
            if (@typeInfo(T) != .optional) {
                @compileError("cannot guarantee value is non-null");
            }
            const Pointer = @typeInfo(@typeInfo(T).optional.child).pointer;
            if (!Pointer.is_const) {
                @compileError("get does not take ownership; can only return const strings");
            }
            return switch (Pointer.size) {
                .one => @compileError("cannot guarantee length of string matches " ++ @typeName(T)),
                .many, .c => value.getString(),
                .slice => std.mem.span(value.getString() orelse return null),
            };
        } else if (std.meta.hasFn(T, "getGObjectType")) {
            return switch (@typeInfo(T)) {
                .@"enum" => @enumFromInt(value.getEnum()),
                .@"struct" => @bitCast(value.getFlags()),
                else => @compileError("cannot extract " ++ @typeName(T) ++ " from Value"),
            };
        } else if (singlePointerChild(T)) |Child| {
            if (@typeInfo(T) != .optional) {
                @compileError("cannot guarantee value is non-null");
            }
            if (Child == gobject.ParamSpec) {
                return value.getParam();
            } else if (Child == glib.Variant) {
                return value.getVariant();
            } else if (std.meta.hasFn(Child, "getGObjectType")) {
                if (isObject(Child)) {
                    return cast(Child, value.getObject() orelse return null);
                } else {
                    return @ptrCast(@alignCast(value.getBoxed() orelse return null));
                }
            } else {
                @compileError("cannot extract " ++ @typeName(T) ++ " from Value");
            }
        } else {
            @compileError("cannot extract " ++ @typeName(T) ++ " from Value");
        }
    }

    /// Sets the contents of `value` to `contents`. The type of `value` must
    /// already be compatible with the type of `contents`.
    ///
    /// This does not take ownership of the value (if applicable).
    pub fn set(value: *gobject.Value, contents: anytype) void {
        const T = @TypeOf(contents);
        if (T == i8) {
            value.setSchar(contents);
        } else if (T == u8) {
            value.setUchar(contents);
        } else if (T == bool) {
            value.setBoolean(@intFromBool(contents));
        } else if (T == c_int) {
            value.setInt(contents);
        } else if (T == c_uint) {
            value.setUint(contents);
        } else if (T == c_long) {
            value.setLong(contents);
        } else if (T == c_ulong) {
            value.setUlong(contents);
        } else if (T == i64) {
            value.setInt64(contents);
        } else if (T == u64) {
            value.setUint64(contents);
        } else if (T == f32) {
            value.setFloat(contents);
        } else if (T == f64) {
            value.setDouble(contents);
        } else if (comptime isCString(T)) {
            // orelse null as temporary workaround for https://github.com/ziglang/zig/issues/12523
            switch (@typeInfo(T)) {
                .pointer => value.setString(contents),
                .optional => value.setString(contents orelse null),
                else => unreachable,
            }
        } else if (std.meta.hasFn(T, "getGObjectType")) {
            switch (@typeInfo(T)) {
                .@"enum" => value.setEnum(@intFromEnum(contents)),
                .@"struct" => value.setFlags(@bitCast(contents)),
                else => @compileError("cannot construct Value from " ++ @typeName(T)),
            }
        } else if (singlePointerChild(T)) |Child| {
            if (Child == gobject.ParamSpec) {
                value.setParam(contents);
            } else if (Child == glib.Variant) {
                value.setVariant(contents);
            } else if (std.meta.hasFn(Child, "getGObjectType")) {
                if (isObject(Child)) {
                    value.setObject(@ptrCast(@alignCast(contents)));
                } else {
                    value.setBoxed(contents);
                }
            } else {
                @compileError("cannot construct Value from " ++ @typeName(T));
            }
        } else {
            @compileError("cannot construct Value from " ++ @typeName(T));
        }
    }
};

test "Value" {
    try testValue(i8, -123);
    try testValue(u8, 123);
    try testValue(bool, true);
    try testValue(c_int, -123);
    try testValue(c_uint, 123);
    try testValue(c_long, -123);
    try testValue(c_ulong, 123);
    try testValue(i64, -(1 << 48));
    try testValue(u64, 1 << 48);
    try testValue(f32, 3.14);
    try testValue(f64, 3.1415926);
    {
        var value = gobject.ext.Value.new([*:0]const u8);
        defer value.unset();
        gobject.ext.Value.set(&value, "Hello, world!");
        try std.testing.expectEqualStrings("Hello, world!", std.mem.span(gobject.ext.Value.get(&value, ?[*:0]const u8).?));
    }
    {
        var value = gobject.ext.Value.new(?[*:0]const u8);
        defer value.unset();
        gobject.ext.Value.set(&value, "Hello, world!");
        try std.testing.expectEqualStrings("Hello, world!", std.mem.span(gobject.ext.Value.get(&value, ?[*:0]const u8).?));
        gobject.ext.Value.set(&value, @as(?[*:0]const u8, null));
        try std.testing.expectEqual(null, gobject.ext.Value.get(&value, ?[*:0]const u8));
    }
    {
        var value = gobject.ext.Value.new([:0]const u8);
        defer value.unset();
        gobject.ext.Value.set(&value, "Hello, world!");
        try std.testing.expectEqualStrings("Hello, world!", gobject.ext.Value.get(&value, ?[:0]const u8).?);
    }
    {
        var value = gobject.ext.Value.new(?[:0]const u8);
        defer value.unset();
        gobject.ext.Value.set(&value, "Hello, world!");
        try std.testing.expectEqualStrings("Hello, world!", gobject.ext.Value.get(&value, ?[:0]const u8).?);
        gobject.ext.Value.set(&value, @as(?[*:0]const u8, null));
        try std.testing.expectEqual(null, gobject.ext.Value.get(&value, ?[:0]const u8));
    }
    {
        const ValueTestObject = extern struct {
            parent_instance: Parent,
            value: c_uint,

            pub const Parent = gobject.Object;
            const Self = @This();

            pub const getGObjectType = gobject.ext.defineClass(Self, .{});

            pub fn new() *Self {
                return gobject.ext.newInstance(Self, .{});
            }

            pub const Class = extern struct {
                parent_class: Parent.Class,

                pub const Instance = Self;
            };
        };

        const obj = ValueTestObject.new();
        defer gobject.Object.unref(gobject.ext.as(gobject.Object, obj));
        obj.value = 123;

        var value = gobject.ext.Value.new(*ValueTestObject);
        defer value.unset();
        gobject.ext.Value.set(&value, obj);
        const stored_obj = gobject.ext.Value.get(&value, ?*ValueTestObject).?;
        try std.testing.expectEqual(123, stored_obj.value);
    }
    {
        const ValueTestBoxed = struct {
            a: u32,
            b: u32,

            pub const getGObjectType = gobject.ext.defineBoxed(@This(), .{});
        };

        const boxed: *const ValueTestBoxed = &.{ .a = 123, .b = 456 };

        var value = gobject.ext.Value.new(*ValueTestBoxed);
        defer value.unset();
        gobject.ext.Value.set(&value, boxed);
        const stored_boxed = gobject.ext.Value.get(&value, ?*ValueTestBoxed).?;
        try std.testing.expectEqual(123, stored_boxed.a);
        try std.testing.expectEqual(456, stored_boxed.b);
    }
    {
        const ValueTestEnum = enum(c_int) {
            one = 1,
            two = 2,
            three = 3,

            pub const getGObjectType = gobject.ext.defineEnum(@This(), .{});
        };

        try testValue(ValueTestEnum, .two);
    }
    {
        const ValueTestFlags = packed struct(c_uint) {
            one: bool = false,
            two: bool = false,
            three: bool = false,
            _padding1: @Type(.{ .int = .{
                .signedness = .unsigned,
                .bits = @bitSizeOf(c_uint) - 3,
            } }) = 0,

            pub const getGObjectType = gobject.ext.defineFlags(@This(), .{});
        };

        try testValue(ValueTestFlags, .{ .one = true, .three = true });
    }
}

fn testValue(comptime T: type, data: T) !void {
    var value = gobject.ext.Value.new(T);
    defer value.unset();
    gobject.ext.Value.set(&value, data);
    try std.testing.expectEqual(data, gobject.ext.Value.get(&value, T));
}

inline fn isObject(comptime T: type) bool {
    return @hasDecl(T, "Class") or @hasDecl(T, "Iface");
}

inline fn isCString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| switch (pointer.size) {
            .one => switch (@typeInfo(pointer.child)) {
                .array => |child| child.child == u8 and std.meta.sentinel(pointer.child) == 0,
                else => false,
            },
            .many, .slice => pointer.child == u8 and std.meta.sentinel(T) == 0,
            .c => pointer.child == u8,
        },
        .optional => |optional| switch (@typeInfo(optional.child)) {
            .pointer => |pointer| switch (pointer.size) {
                .one => switch (@typeInfo(pointer.child)) {
                    .array => |child| child.child == u8 and std.meta.sentinel(pointer.child) == 0,
                    else => false,
                },
                .many, .slice => pointer.child == u8 and std.meta.sentinel(optional.child) == 0,
                .c => false,
            },
            else => false,
        },
        else => false,
    };
}

inline fn singlePointerChild(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| switch (pointer.size) {
            .one, .c => pointer.child,
            else => null,
        },
        .optional => |optional| switch (@typeInfo(optional.child)) {
            .pointer => |pointer| switch (pointer.size) {
                .one => pointer.child,
                else => null,
            },
            else => null,
        },
        else => null,
    };
}
