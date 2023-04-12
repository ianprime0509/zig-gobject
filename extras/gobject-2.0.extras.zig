const glib = @import("glib-2.0");
const gobject = @import("gobject-2.0");
const std = @import("std");

pub const namespace = struct {
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

    /// Returns the GObject `Type` corresponding to the given type.
    pub fn typeFor(comptime T: type) gobject.Type {
        const typeInfo = @typeInfo(T);
        // Types manually extracted from gtype.h since they don't seem to show up in GIR
        if (typeInfo == .Pointer and comptime isRegisteredType(typeInfo.Pointer.child)) {
            return typeInfo.Pointer.child.getType();
        } else if (T == void) {
            return typeMakeFundamental(1);
        } else if (T == i8) {
            return typeMakeFundamental(3);
        } else if (T == u8) {
            return typeMakeFundamental(4);
        } else if (T == bool) {
            return typeMakeFundamental(5);
        } else if (T == c_int) {
            return typeMakeFundamental(6);
        } else if (T == c_uint) {
            return typeMakeFundamental(7);
        } else if (T == c_long) {
            return typeMakeFundamental(8);
        } else if (T == c_ulong) {
            return typeMakeFundamental(9);
        } else if (T == i64) {
            return typeMakeFundamental(10);
        } else if (T == u64) {
            return typeMakeFundamental(11);
        } else if (T == f32) {
            return typeMakeFundamental(14);
        } else if (T == f64) {
            return typeMakeFundamental(15);
        } else if (comptime isCString(T)) {
            return typeMakeFundamental(16);
        } else if (T == *gobject.ParamSpec) {
            return typeMakeFundamental(19);
        } else if (T == *glib.Variant) {
            return typeMakeFundamental(21);
        } else if (typeInfo == .Pointer or (typeInfo == .Optional and @typeInfo(typeInfo.Optional.child) == .Pointer)) {
            return typeMakeFundamental(17);
        } else if (typeInfo == .Enum and typeInfo.Enum.tag_type == c_int) {
            return Enum;
        } else if (typeInfo == .Struct and typeInfo.Struct.backing_integer == c_uint) {
            return Flags;
        } else {
            @compileError("unable to determine GObject type for " ++ @typeName(T));
        }
    }

    pub const RegisterTypeOptions = struct {
        name: ?[:0]const u8 = null,
        flags: gobject.TypeFlags = .{},
    };

    /// Registers a new class type in the GObject type system.
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
    /// - Optionally, it may have a public declaration named `Private` which, if
    ///   present, must be refer to a struct type representing the instance's private
    ///   data
    /// - `Private` must have a public declaration named `offset` of type `c_int`, which
    ///   will be used to store the private data offset and should not be modified by
    ///   the user (it must be `var` to allow the class initialization logic to set it,
    ///   however)
    ///
    /// The following lifecycle methods are supported through public functions declared
    /// on the instance or class struct, as indicated below:
    ///
    /// - `Class.base_init` - `fn (*Class) callconv(.C) void`
    /// - `Class.base_finalize` - `fn (*Class) callconv(.C) void`
    /// - `Class.init` - `fn (*Class) callconv(.C) void`
    /// - `Class.finalize` - `fn (*Class) callconv(.C) void`
    /// - `Self.init` - `fn (*Self, *Class) callconv(.C) void`
    ///
    /// It is also highly recommended to mix all parent methods into the instance and
    /// class structs. In the instance struct, this is `pub usingnamespace
    /// Parent.Methods(Self)`; in the class struct, this is `pub usingnamespace
    /// Parent.Class.Methods(Class)` and `Parent.Class.VirtualMethods(Class,
    /// Self)`. This is not enforced by the type registration logic, and has no bearing
    /// on the validity of the type from a GObject perspective, but other helper methods
    /// may depend on base class methods being present.
    pub fn registerType(comptime Self: type, comptime options: RegisterTypeOptions) fn () callconv(.C) gobject.Type {
        const self_info = @typeInfo(Self);
        if (self_info != .Struct or self_info.Struct.layout != .Extern) {
            @compileError("an instance type must be an extern struct");
        }

        if (!@hasDecl(Self, "Parent")) {
            @compileError("a class type must have a declaration named Parent pointing to the parent type");
        }
        const parent_info = @typeInfo(Self.Parent);
        if (parent_info != .Struct or parent_info.Struct.layout != .Extern or !@hasDecl(Self.Parent, "getType")) {
            @compileError("the defined parent type " ++ @typeName(Self.Parent) ++ " does not appear to be a GObject class type");
        }
        if (self_info.Struct.fields.len == 0 or self_info.Struct.fields[0].type != Self.Parent) {
            @compileError("the first field of the instance struct must have type " ++ @typeName(Self.Parent));
        }

        if (!@hasDecl(Self, "Class")) {
            @compileError("a class type must have a member named Class pointing to the class record");
        }
        const class_info = @typeInfo(Self.Class);
        if (class_info != .Struct or class_info.Struct.layout != .Extern) {
            @compileError("a class type must be an extern struct");
        }
        if (!@hasDecl(Self.Class, "Instance") or Self.Class.Instance != Self) {
            @compileError("a class type must have a declaration named Instance pointing to the instance type");
        }
        if (class_info.Struct.fields.len == 0 or class_info.Struct.fields[0].type != Self.Parent.Class) {
            @compileError("the first field of the class struct must have type " ++ @typeName(Self.Parent.Class));
        }

        if (@hasDecl(Self, "Private")) {
            if (@typeInfo(Self.Private) != .Struct or !@hasDecl(Self.Private, "offset") or @TypeOf(Self.Private.offset) != c_int) {
                @compileError("private type must be a struct with an offset declaration of type c_int to store the private data offset");
            }
        }

        if (@hasDecl(Self.Class, "baseInit")) {
            assertTypesEqual("Class.baseInit", fn (*Self.Class) callconv(.C) void, @TypeOf(Self.Class.baseInit));
        }
        if (@hasDecl(Self.Class, "baseFinalize")) {
            assertTypesEqual("Class.baseFinalize", fn (*Self.Class) callconv(.C) void, @TypeOf(Self.Class.baseFinalize));
        }
        if (@hasDecl(Self.Class, "init")) {
            assertTypesEqual("Class.init", fn (*Self.Class) callconv(.C) void, @TypeOf(Self.Class.init));
        }
        if (@hasDecl(Self.Class, "finalize")) {
            assertTypesEqual("Class.finalize", fn (*Self.Class) callconv(.C) void, @TypeOf(Self.Class.finalize));
        }
        if (@hasDecl(Self, "init")) {
            assertTypesEqual("init", fn (*Self, *Self.Class) callconv(.C) void, @TypeOf(Self.init));
        }

        return struct {
            var registered_type: gobject.Type = 0;

            pub fn getType() callconv(.C) gobject.Type {
                if (glib.Once.initEnter(&registered_type)) {
                    const classInitFunc = struct {
                        fn classInit(class: *Self.Class) callconv(.C) void {
                            if (@hasDecl(Self.Class, "parent")) {
                                Self.Class.parent = @ptrCast(*Self.Parent.Class, @alignCast(@alignOf(*Self.Parent.Class), class.peekParent()));
                            }
                            if (@hasDecl(Self, "Private")) {
                                gobject.TypeClass.adjustPrivateOffset(class, &Self.Private.offset);
                            }
                            if (@hasDecl(Self.Class, "init")) {
                                Self.Class.init(class);
                            }
                        }
                    }.classInit;
                    const info = gobject.TypeInfo{
                        .class_size = @sizeOf(Self.Class),
                        .base_init = if (@hasDecl(Self, "baseInit")) @ptrCast(gobject.BaseInitFunc, &Self.baseInit) else null,
                        .base_finalize = if (@hasDecl(Self, "baseFinalize")) @ptrCast(gobject.BaseFinalizeFunc, &Self.baseFinalize) else null,
                        .class_init = @ptrCast(gobject.ClassInitFunc, &classInitFunc),
                        .class_finalize = if (@hasDecl(Self.Class, "finalize")) @ptrCast(gobject.ClassFinalizeFunc, &Self.Class.finalize) else null,
                        .class_data = null,
                        .instance_size = @sizeOf(Self),
                        .n_preallocs = 0,
                        .instance_init = if (@hasDecl(Self, "init")) @ptrCast(gobject.InstanceInitFunc, &Self.init) else null,
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
                    const type_id = gobject.typeRegisterStatic(Self.Parent.getType(), type_name, &info, options.flags);
                    if (@hasDecl(Self, "Private")) {
                        Self.Private.offset = gobject.typeAddInstancePrivate(type_id, @sizeOf(Self.Private));
                    }
                    glib.Once.initLeave(&registered_type, type_id);
                }
                return registered_type;
            }
        }.getType;
    }
};

pub fn TypeInstanceMethods(comptime Self: type) type {
    return struct {
        /// Casts this to another type, or returns null if this is not an instance of the type.
        pub fn cast(self: *Self, comptime T: type) ?*T {
            return if (self.isA(T)) self.castUnchecked(T) else null;
        }

        /// Casts this to another type, without checking whether such a cast is actually valid.
        pub fn castUnchecked(self: *Self, comptime T: type) *T {
            return @ptrCast(*T, @alignCast(@alignOf(*T), self));
        }

        /// Returns whether this is an instance of the given type or some sub-type.
        pub fn isA(self: *Self, comptime T: type) bool {
            return gobject.typeCheckInstanceIsA(self.castUnchecked(gobject.TypeInstance), gobject.typeFor(T));
        }

        /// Returns the offset of a private data field relative to the instance struct.
        pub fn offsetOfPrivate(comptime field_name: []const u8) isize {
            if (!@hasDecl(Self, "Private")) {
                @compileError("no private data available for " ++ @typeName(Self));
            }
            return @as(isize, Self.Private.offset) + @offsetOf(Self.Private, field_name);
        }

        /// Returns the private data struct for this object.
        pub fn private(self: *Self) *PrivateType(Self) {
            return @intToPtr(*Self.Private, @ptrToInt(self) +% @bitCast(usize, @as(isize, Self.Private.offset)));
        }

        fn PrivateType(comptime T: type) type {
            return if (@hasDecl(T, "Private")) T.Private else @compileError("no private data available for " ++ @typeName(T));
        }
    };
}

pub fn TypeClassMethods(comptime Self: type) type {
    return struct {
        /// Casts this to another type, without checking whether such a cast is actually valid.
        pub fn castUnchecked(self: *Self, comptime T: type) *T {
            return @ptrCast(*T, @alignCast(@alignOf(*T), self));
        }
    };
}

pub fn ObjectMethods(comptime Self: type) type {
    return struct {
        /// Creates a new instance of this object type with the given properties.
        pub fn newWith(properties: anytype) *Self {
            const typeInfo = @typeInfo(@TypeOf(properties)).Struct;
            const n_props = typeInfo.fields.len;
            var names: [n_props][*:0]const u8 = undefined;
            var values: [n_props]gobject.Value = undefined;
            inline for (typeInfo.fields, 0..) |field, i| {
                names[i] = field.name ++ "\x00";
                values[i] = gobject.Value.wrap(@field(properties, field.name));
            }
            defer for (&values) |*value| value.unset();
            // TODO: the names parameter should actually be [*][*:0]const u8
            return gobject.Object.newWithProperties(Self.getType(), n_props, @ptrCast([*][*:0]u8, &names), &values).castUnchecked(Self);
        }

        /// Safely casts this object to an instance of `T`, emitting a compilation error if the safety of the cast cannot be guaranteed.
        pub fn as(self: *Self, comptime T: type) *T {
            if (T == Self) {
                return self;
            }

            if (@hasDecl(Self, "Implements")) {
                inline for (Self.Implements) |implements| {
                    if (implements == T) {
                        return self.castUnchecked(T);
                    }
                }
            }

            comptime var curr_type = Self;
            inline while (@hasDecl(curr_type, "Parent")) {
                curr_type = curr_type.Parent;
                if (curr_type == T) {
                    return self.castUnchecked(T);
                }
            }

            @compileError("type is not guaranteed to be compatible with " ++ @typeName(T));
        }
    };
}

pub fn ObjectClassMethods(comptime Self: type) type {
    return struct {
        /// Safely casts this class to an instance of `T`, emitting a compilation error if the safety of the cast cannot be guaranteed.
        pub fn as(class: *Self, comptime T: type) *T {
            if (T == Self) {
                return class;
            }

            comptime var curr_type = Self;
            inline while (@hasDecl(curr_type.Instance, "Parent")) {
                curr_type = curr_type.Instance.Parent.Class;
                if (curr_type == T) {
                    return @ptrCast(*T, @alignCast(@alignOf(*T), class));
                }
            }

            @compileError("type is not guaranteed to be compatible with " ++ @typeName(T));
        }

        // Special case not exposed through normal GIR
        pub usingnamespace TypeClassMethods(Self);
    };
}

pub fn Value(comptime Self: type) type {
    return struct {
        /// Returns a new `Value` intended to hold data of the given type.
        pub fn new(comptime T: type) Self {
            var value = std.mem.zeroes(Self);
            _ = value.init(gobject.typeFor(T));
            return value;
        }

        /// Wraps a value in a `Value`.
        ///
        /// This does not take ownership of the value (if applicable).
        pub fn wrap(value: anytype) Self {
            comptime var T = @TypeOf(value);
            const typeInfo = @typeInfo(T);
            var wrapped: Self = undefined;
            if (typeInfo == .Pointer and comptime isRegisteredType(typeInfo.Pointer.child)) {
                wrapped = new(T);
                if (typeInfo.Pointer.child.getType() == gobject.Boxed) {
                    wrapped.setBoxed(value);
                } else {
                    wrapped.setObject(@ptrCast(*gobject.Object, value));
                }
            } else if (T == i8) {
                wrapped = new(T);
                wrapped.setSchar(value);
            } else if (T == u8) {
                wrapped = new(T);
                wrapped.setUchar(value);
            } else if (T == bool) {
                wrapped = new(T);
                wrapped.setBoolean(value);
            } else if (T == c_int) {
                wrapped = new(T);
                wrapped.setInt(value);
            } else if (T == c_uint) {
                wrapped = new(T);
                wrapped.setUint(value);
            } else if (T == c_long) {
                wrapped = new(T);
                wrapped.setLong(value);
            } else if (T == c_ulong) {
                wrapped = new(T);
                wrapped.setUlong(value);
            } else if (T == i64) {
                wrapped = new(T);
                wrapped.setInt64(value);
            } else if (T == u64) {
                wrapped = new(T);
                wrapped.setUint64(value);
            } else if (T == f32) {
                wrapped = new(T);
                wrapped.setFloat(value);
            } else if (T == f64) {
                wrapped = new(T);
                wrapped.setDouble(value);
            } else if (comptime isCString(T)) {
                wrapped = new(T);
                wrapped.setString(value);
            } else if (T == *gobject.ParamSpec) {
                wrapped = new(T);
                wrapped.setParam(value);
            } else if (T == *glib.Variant) {
                wrapped = new(T);
                wrapped.setVariant(value);
            } else if (typeInfo == .Pointer or (typeInfo == .Optional and @typeInfo(typeInfo.Optional.child) == .Pointer)) {
                wrapped = new(T);
                wrapped.setPointer(value);
            } else if (typeInfo == .Enum and typeInfo.Enum.tag_type == c_int) {
                wrapped = new(T);
                wrapped.setEnum(@enumToInt(value));
            } else if (typeInfo == .Struct and typeInfo.Struct.backing_integer == c_uint) {
                wrapped = new(T);
                wrapped.setFlags(@bitCast(c_uint, value));
            } else {
                @compileError("cannot construct Value containing " ++ @typeName(T));
            }
            return wrapped;
        }
    };
}

fn assertTypesEqual(comptime name: []const u8, comptime Expected: type, comptime Actual: type) void {
    if (Expected != Actual) {
        @compileError(std.fmt.comptimePrint("expected type of {s} to be {s}, found {s}", .{ name, @typeName(Expected), @typeName(Actual) }));
    }
}

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

fn isRegisteredType(comptime T: type) bool {
    return std.meta.trait.hasFn("getType")(T) and @TypeOf(T.getType) == fn () callconv(.C) gobject.Type;
}