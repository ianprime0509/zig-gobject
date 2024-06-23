const glib = @import("glib2");
const gobject = @import("gobject2");
const std = @import("std");

/// The fundamental type from which all interfaces are derived.
pub const Interface = typeMakeFundamental(2);

/// The fundamental type from which all enumeration types are derived.
pub const Enum = typeMakeFundamental(12);

/// The fundamental type from which all boxed types are derived.
pub const Flags = typeMakeFundamental(13);

/// The fundamental type from which all boxed types are derived.
pub const Boxed = typeMakeFundamental(18);

/// A translation of the `G_TYPE_MAKE_FUNDAMENTAL` macro.
pub fn typeMakeFundamental(x: usize) gobject.Type {
    return x << gobject.TYPE_FUNDAMENTAL_SHIFT;
}

/// Fundamental types.
pub const types = struct {
    // Values taken from gtype.h.
    pub const invalid = typeMakeFundamental(0);
    pub const none = typeMakeFundamental(1);
    pub const interface = typeMakeFundamental(2);
    pub const char = typeMakeFundamental(3);
    pub const uchar = typeMakeFundamental(4);
    pub const boolean = typeMakeFundamental(5);
    pub const int = typeMakeFundamental(6);
    pub const uint = typeMakeFundamental(7);
    pub const long = typeMakeFundamental(8);
    pub const ulong = typeMakeFundamental(9);
    pub const int64 = typeMakeFundamental(10);
    pub const uint64 = typeMakeFundamental(11);
    pub const @"enum" = typeMakeFundamental(12);
    pub const flags = typeMakeFundamental(13);
    pub const float = typeMakeFundamental(14);
    pub const double = typeMakeFundamental(15);
    pub const string = typeMakeFundamental(16);
    pub const pointer = typeMakeFundamental(17);
    pub const boxed = typeMakeFundamental(18);
    pub const param = typeMakeFundamental(19);
    pub const object = typeMakeFundamental(20);
    pub const variant = typeMakeFundamental(21);
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

pub fn DefineClassOptions(comptime Self: type) type {
    return struct {
        /// The name of the type. The default is to use the base type name of
        /// `Self`.
        name: ?[:0]const u8 = null,
        flags: gobject.TypeFlags = .{},
        baseInit: ?*const fn (*Self.Class) callconv(.C) void = null,
        baseFinalize: ?*const fn (*Self.Class) callconv(.C) void = null,
        classInit: ?*const fn (*Self.Class) callconv(.C) void = null,
        classFinalize: ?*const fn (*Self.Class) callconv(.C) void = null,
        instanceInit: ?*const fn (*Self, *Self.Class) callconv(.C) void = null,
        /// Interface implementations, created using `implement`.
        ///
        /// The interface types specified here must match the top-level
        /// `Implements` member of `Self`, which is expected to be an array of
        /// all interface types implemented by `Self`.
        implements: []const InterfaceImplementation = &.{},
        /// If non-null, will be set to the instance of the parent class when
        /// the class is initialized.
        parent_class: ?**Self.Parent.Class = null,
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
        init: ?*const fn (*Iface.Iface) callconv(.C) void = null,
        finalize: ?*const fn (*Iface.Iface) callconv(.C) void = null,
    };
}

/// Specifies an interface type to be implemented and the lifecycle functions to
/// do so.
pub fn implement(comptime Iface: type, comptime options: ImplementOptions(Iface)) InterfaceImplementation {
    return .{
        .Iface = Iface,
        .info = .{
            .interface_init = @ptrCast(options.init),
            .interface_finalize = @ptrCast(options.finalize),
            .interface_data = null,
        },
    };
}

/// Sets up a class type in the GObject type system, returning the associated
/// `getGObjectType` function.
///
/// The `Self` parameter is the instance struct for the type. There are several
/// constraints on this type:
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
pub fn defineClass(comptime Self: type, comptime options: DefineClassOptions(Self)) fn () callconv(.C) gobject.Type {
    const self_info = @typeInfo(Self);
    if (self_info != .Struct or self_info.Struct.layout != .@"extern") {
        @compileError("an instance type must be an extern struct");
    }

    if (!@hasDecl(Self, "Parent")) {
        @compileError("a class type must have a declaration named Parent pointing to the parent type");
    }
    const parent_info = @typeInfo(Self.Parent);
    if (parent_info != .Struct or parent_info.Struct.layout != .@"extern" or !@hasDecl(Self.Parent, "getGObjectType")) {
        @compileError("the defined parent type " ++ @typeName(Self.Parent) ++ " does not appear to be a GObject class type");
    }
    if (self_info.Struct.fields.len == 0 or self_info.Struct.fields[0].type != Self.Parent) {
        @compileError("the first field of the instance struct must have type " ++ @typeName(Self.Parent));
    }

    if (!@hasDecl(Self, "Class")) {
        @compileError("a class type must have a member named Class pointing to the class record");
    }
    const class_info = @typeInfo(Self.Class);
    if (class_info != .Struct or class_info.Struct.layout != .@"extern") {
        @compileError("a class type must be an extern struct");
    }
    if (!@hasDecl(Self.Class, "Instance") or Self.Class.Instance != Self) {
        @compileError("a class type must have a declaration named Instance pointing to the instance type");
    }
    if (class_info.Struct.fields.len == 0 or class_info.Struct.fields[0].type != Self.Parent.Class) {
        @compileError("the first field of the class struct must have type " ++ @typeName(Self.Parent.Class));
    }

    return struct {
        var registered_type: gobject.Type = 0;

        pub fn getGObjectType() callconv(.C) gobject.Type {
            if (glib.Once.initEnter(&registered_type) != 0) {
                const classInitFunc = struct {
                    fn classInit(class: *Self.Class) callconv(.C) void {
                        if (options.parent_class) |parent_class| {
                            const parent = gobject.TypeClass.peekParent(class.as(gobject.TypeClass));
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
                const info = gobject.TypeInfo{
                    .class_size = @sizeOf(Self.Class),
                    .base_init = @ptrCast(options.baseInit),
                    .base_finalize = @ptrCast(options.baseFinalize),
                    .class_init = @ptrCast(&classInitFunc),
                    .class_finalize = @ptrCast(options.classFinalize),
                    .class_data = null,
                    .instance_size = @sizeOf(Self),
                    .n_preallocs = 0,
                    .instance_init = @ptrCast(options.instanceInit),
                    .value_table = null,
                };

                const type_name = if (options.name) |name| name else blk: {
                    var self_name: [:0]const u8 = @typeName(Self);
                    const last_dot = std.mem.lastIndexOfScalar(u8, self_name, '.');
                    if (last_dot) |pos| {
                        self_name = self_name[pos + 1 ..];
                    }
                    break :blk self_name;
                };
                const type_id = gobject.typeRegisterStatic(Self.Parent.getGObjectType(), type_name, &info, options.flags);

                if (options.private) |private| {
                    private.offset.* = gobject.typeAddInstancePrivate(type_id, @sizeOf(private.Type));
                }

                {
                    const Implements = if (@hasDecl(Self, "Implements")) Self.Implements else [_]type{};
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

pub fn SignalHandler(comptime Itype: type, comptime param_types: []const type, comptime DataType: type, comptime ReturnType: type) type {
    return *const @Type(.{ .Fn = .{
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

/// Sets up a signal definition, returning a type with various helpers
/// related to the signal.
///
/// The returned type contains the following members:
/// - `id` - a c_uint which is initially 0 but will be set to the signal
///   ID when the signal is registered
/// - `register` - a function with a `RegisterSignalOptions` parameter
///   which is used to register the signal in the GObject type system.
///   This function should generally be called in Itype's class
///   initializer.
/// - `emit` - a function which emits the signal on an object. The `emit`
///   function takes the following parameters:
///   - `target: Itype` - the target object
///   - `detail: ?[:0]const u8` - the signal detail argument
///   - `params: EmitParams` - signal parameters. `EmitParams` is a tuple
///     with field types matching `param_types`.
///   - `return_value: ?*ReturnValue` - optional pointer to where the
///     return value of the signal should be stored
/// - `connect` - a function which connects the signal. The signature of
///   this function is analogous to all other `connect` functions in
///   this library.
pub fn defineSignal(
    comptime name: [:0]const u8,
    comptime Itype: type,
    comptime param_types: []const type,
    comptime ReturnType: type,
) type {
    const EmitParams = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = fields: {
            var fields: [param_types.len]std.builtin.Type.StructField = undefined;
            for (param_types, &fields, 0..) |ParamType, *field, i| {
                field.* = .{
                    .name = std.fmt.comptimePrint("{}", .{i}),
                    .type = ParamType,
                    .default_value = null,
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
        pub var id: c_uint = 0;

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

        pub fn emit(target: *Itype, detail: ?[:0]const u8, params: EmitParams, return_value: ?*ReturnType) void {
            var emit_params: [param_types.len + 1]gobject.Value = undefined;
            emit_params[0] = gobject.ext.Value.newFrom(target);
            inline for (params, emit_params[1..]) |param, *emit_param| {
                emit_param.* = gobject.ext.Value.newFrom(param);
            }
            defer for (&emit_params) |*emit_param| emit_param.unset();
            const detail_quark = if (detail) |detail_str| glib.quarkFromString(detail_str) else 0;
            var raw_return_value: gobject.Value = undefined;
            gobject.signalEmitv(&emit_params, id, detail_quark, &raw_return_value);
            if (return_value) |return_value_location| {
                return_value_location.* = gobject.ext.Value.get(&raw_return_value, ReturnType);
            }
        }

        pub fn connect(
            target: anytype,
            comptime T: type,
            callback: SignalHandler(@typeInfo(@TypeOf(target)).Pointer.child, param_types, T, ReturnType),
            data: T,
            connect_options: struct { after: bool = false },
        ) c_ulong {
            return gobject.signalConnectData(
                @ptrCast(@alignCast(target.as(Itype))),
                name,
                @as(gobject.Callback, @ptrCast(callback)),
                data,
                null,
                .{ .after = connect_options.after },
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
    if (self_info != .Pointer or self_info.Pointer.size != .One) {
        @compileError("cannot cast a non-pointer type");
    }
    const Self = self_info.Pointer.child;

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
    const typeInfo = @typeInfo(@TypeOf(properties)).Struct;
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
    /// Returns a new `Value` intended to hold data of the given type.
    pub fn new(comptime T: type) gobject.Value {
        var value = std.mem.zeroes(gobject.Value);
        _ = value.init(gobject.ext.typeFor(T));
        return value;
    }

    /// Returns a new `Value` with the given contents.
    ///
    /// This does not take ownership of the value (if applicable).
    pub fn newFrom(contents: anytype) gobject.Value {
        const T = @TypeOf(contents);
        var value: gobject.Value = new(T);
        if (T == void) {
            // Nothing to set.
        } else if (T == i8) {
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
            value.setString(contents);
        } else if (std.meta.hasFn(T, "getGObjectType")) {
            switch (@typeInfo(T)) {
                .Enum => value.setEnum(@intFromEnum(contents)),
                .Struct => value.setFlags(@bitCast(contents)),
                else => @compileError("cannot construct Value from " ++ @typeName(T)),
            }
        } else if (singlePointerChild(T)) |Child| {
            if (Child == gobject.ParamSpec) {
                value.setParam(contents);
            } else if (Child == glib.Variant) {
                value.setVariant(contents);
            } else if (std.meta.hasFn(Child, "getGObjectType")) {
                const type_instance = as(gobject.TypeInstance, contents);
                if (gobject.typeCheckInstanceIsFundamentallyA(type_instance, types.object) != 0) {
                    value.setObject(@ptrCast(@alignCast(contents)));
                } else if (gobject.typeCheckInstanceIsFundamentallyA(type_instance, types.boxed) != 0) {
                    value.setBoxed(contents);
                } else {
                    @panic("unrecognized GObject type " ++ @typeName(T));
                }
            } else {
                @compileError("cannot construct Value from " ++ @typeName(T));
            }
        } else {
            @compileError("cannot construct Value from " ++ @typeName(T));
        }
        return value;
    }

    /// Extracts a value of the given type.
    ///
    /// This does not return an owned value (if applicable): the caller must
    /// copy/ref/etc. the value if needed beyond the lifetime of the container.
    pub fn get(value: *const gobject.Value, comptime T: type) T {
        if (T == void) {
            return {};
        } else if (T == i8) {
            return value.getSchar();
        } else if (T == u8) {
            return value.getUchar();
        } else if (T == bool) {
            return value.getBoolean() != 0;
        } else if (T == c_int) {
            return value.getInt();
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
        } else if (T == [*:0]const u8) {
            // We do not accept all the various string types we accept in the
            // newFrom method here because we are not transferring ownership
            return value.getString();
        } else if (std.meta.hasFn(T, "getGObjectType")) {
            return switch (@typeInfo(T)) {
                .Enum => @enumFromInt(value.getEnum()),
                .Struct => @bitCast(value.getFlags()),
                else => @compileError("cannot extract " ++ @typeName(T) ++ " from Value"),
            };
        } else if (singlePointerChild(T)) |Child| {
            if (Child == gobject.ParamSpec) {
                return value.getParam();
            } else if (Child == glib.Variant) {
                return value.getVariant();
            } else if (std.meta.hasFn(Child, "getGObjectType")) {
                if (gobject.typeCheckIsFundamentallyA(value.g_type, types.object) != 0) {
                    return cast(Child, value.getObject() orelse return null);
                } else if (gobject.typeCheckInstanceIsFundamentallyA(value.g_type, types.boxed) != 0) {
                    return @ptrCast(@alignCast(value.getBoxed() orelse return null));
                } else {
                    @panic("unrecognized GObject type " ++ @typeName(T));
                }
            }
        } else {
            @compileError("cannot extract " ++ @typeName(T) ++ " from Value");
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
            .Many, .Slice => info.child == u8 and std.meta.sentinel(T) == @as(u8, 0),
            .C => info.child == u8,
        },
        else => false,
    };
}

fn singlePointerChild(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .Pointer => |pointer| switch (pointer.size) {
            .One, .C => pointer.child,
            else => null,
        },
        .Optional => |optional| switch (@typeInfo(optional.child)) {
            .Pointer => |pointer| switch (pointer.size) {
                .One => pointer.child,
                else => null,
            },
        },
        else => null,
    };
}
