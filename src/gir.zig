const std = @import("std");
const xml = @import("xml");
const fmt = std.fmt;
const io = std.io;
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const ComptimeStringMap = std.ComptimeStringMap;

const ns = struct {
    pub const core = "http://www.gtk.org/introspection/core/1.0";
    pub const c = "http://www.gtk.org/introspection/c/1.0";
    pub const glib = "http://www.gtk.org/introspection/glib/1.0";
};

pub const Error = error{InvalidGir} || Allocator.Error;

pub const Repository = struct {
    includes: []const Include = &.{},
    packages: []const Package = &.{},
    namespace: Namespace,
    arena: ArenaAllocator,

    pub fn parse(allocator: Allocator, reader: anytype) (error{InvalidGir} || @TypeOf(reader).Error || Allocator.Error)!Repository {
        var r = xml.reader(allocator, reader, xml.encoding.Utf8Decoder{}, .{});
        defer r.deinit();
        return parseXml(allocator, &r) catch |err| switch (err) {
            error.CannotUndeclareNsPrefix,
            error.DuplicateAttribute,
            error.InvalidQName,
            error.MismatchedEndTag,
            error.UndeclaredEntityReference,
            error.UndeclaredNsPrefix,
            error.InvalidEncoding,
            error.Overflow,
            error.SyntaxError,
            error.UnexpectedEndOfInput,
            error.InvalidUtf8,
            => return error.InvalidGir,
            else => |other| return other,
        };
    }

    pub fn deinit(self: *Repository) void {
        self.arena.deinit();
    }

    fn parseXml(allocator: Allocator, reader: anytype) !Repository {
        var repository: ?Repository = null;
        while (try reader.next()) |event| {
            switch (event) {
                .element_start => |e| if (e.name.is(ns.core, "repository")) {
                    repository = try parseInternal(allocator, reader.children());
                } else {
                    try reader.children().skip();
                },
                else => {},
            }
        }
        return repository orelse error.InvalidGir;
    }

    fn parseInternal(a: Allocator, children: anytype) !Repository {
        var arena = ArenaAllocator.init(a);
        const allocator = arena.allocator();

        var includes = ArrayListUnmanaged(Include){};
        var packages = ArrayListUnmanaged(Package){};
        var namespace: ?Namespace = null;

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "include")) {
                    try includes.append(allocator, try Include.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "package")) {
                    try packages.append(allocator, try Package.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "namespace")) {
                    namespace = try Namespace.parse(allocator, child, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .includes = try includes.toOwnedSlice(allocator),
            .packages = try packages.toOwnedSlice(allocator),
            .namespace = namespace orelse return error.InvalidGir,
            .arena = arena,
        };
    }
};

pub const Include = struct {
    name: []const u8,
    version: []const u8,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype) !Include {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "version")) {
                version = try allocator.dupe(u8, attr.value);
            }
        }

        try children.skip();

        return .{
            .name = name orelse return error.InvalidGir,
            .version = version orelse return error.InvalidGir,
        };
    }
};

pub const Package = struct {
    name: []const u8,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype) !Package {
        var name: ?[]const u8 = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            }
        }

        try children.skip();

        return .{
            .name = name orelse return error.InvalidGir,
        };
    }
};

pub const Namespace = struct {
    name: []const u8,
    version: []const u8,
    aliases: []const Alias = &.{},
    classes: []const Class = &.{},
    interfaces: []const Interface = &.{},
    records: []const Record = &.{},
    unions: []const Union = &.{},
    bit_fields: []const BitField = &.{},
    enums: []const Enum = &.{},
    functions: []const Function = &.{},
    callbacks: []const Callback = &.{},
    constants: []const Constant = &.{},

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype) !Namespace {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var aliases = ArrayListUnmanaged(Alias){};
        var classes = ArrayListUnmanaged(Class){};
        var interfaces = ArrayListUnmanaged(Interface){};
        var records = ArrayListUnmanaged(Record){};
        var unions = ArrayListUnmanaged(Union){};
        var bit_fields = ArrayListUnmanaged(BitField){};
        var enums = ArrayListUnmanaged(Enum){};
        var functions = ArrayListUnmanaged(Function){};
        var callbacks = ArrayListUnmanaged(Callback){};
        var constants = ArrayListUnmanaged(Constant){};

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "version")) {
                version = try allocator.dupe(u8, attr.value);
            }
        }

        if (name == null) {
            return error.InvalidGir;
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "alias")) {
                    try aliases.append(allocator, try Alias.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "class")) {
                    try classes.append(allocator, try Class.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "interface")) {
                    try interfaces.append(allocator, try Interface.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "record")) {
                    try records.append(allocator, try Record.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "union")) {
                    try unions.append(allocator, try Union.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "bitfield")) {
                    try bit_fields.append(allocator, try BitField.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "enumeration")) {
                    try enums.append(allocator, try Enum.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "callback")) {
                    try callbacks.append(allocator, try Callback.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(allocator, try Constant.parse(allocator, child, children.children(), name.?));
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name.?,
            .version = version orelse return error.InvalidGir,
            .aliases = try aliases.toOwnedSlice(allocator),
            .classes = try classes.toOwnedSlice(allocator),
            .interfaces = try interfaces.toOwnedSlice(allocator),
            .records = try records.toOwnedSlice(allocator),
            .unions = try unions.toOwnedSlice(allocator),
            .bit_fields = try bit_fields.toOwnedSlice(allocator),
            .enums = try enums.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .callbacks = try callbacks.toOwnedSlice(allocator),
            .constants = try constants.toOwnedSlice(allocator),
        };
    }
};

pub const Alias = struct {
    name: []const u8,
    type: Type,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Alias {
        var name: ?[]const u8 = null;
        var @"type": ?Type = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    @"type" = try Type.parse(allocator, child, children.children(), current_ns);
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Class = struct {
    name: []const u8,
    parent: ?Name = null,
    implements: []const Implements = &.{},
    fields: []const Field,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    get_type: []const u8,
    type_struct: ?[]const u8 = null,
    final: bool = false,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Class) Function {
        return Function.forGetType(self, self.symbol_prefix, true);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Class {
        var name: ?[]const u8 = null;
        var parent: ?Name = null;
        var implements = ArrayListUnmanaged(Implements){};
        var fields = ArrayListUnmanaged(Field){};
        var functions = ArrayListUnmanaged(Function){};
        var constructors = ArrayListUnmanaged(Constructor){};
        var methods = ArrayListUnmanaged(Method){};
        var virtual_methods = ArrayListUnmanaged(VirtualMethod){};
        var signals = ArrayListUnmanaged(Signal){};
        var constants = ArrayListUnmanaged(Constant){};
        var get_type: ?[]const u8 = null;
        var type_struct: ?[]const u8 = null;
        var final = false;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "parent")) {
                parent = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "type-struct")) {
                type_struct = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "final")) {
                final = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "implements")) {
                    try implements.append(allocator, try Implements.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "field")) {
                    try fields.append(allocator, try Field.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(allocator, try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(allocator, try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "virtual-method")) {
                    try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.glib, "signal")) {
                    try signals.append(allocator, try Signal.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(allocator, try Constant.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        // For some reason, the final attribute is very rarely used. A more
        // reliable indicator seems to be the number of fields in the class (0
        // means it's final).
        if (fields.items.len == 0) {
            final = true;
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parent = parent,
            .implements = try implements.toOwnedSlice(allocator),
            .fields = try fields.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .virtual_methods = try virtual_methods.toOwnedSlice(allocator),
            .signals = try signals.toOwnedSlice(allocator),
            .constants = try constants.toOwnedSlice(allocator),
            .get_type = get_type orelse return error.InvalidGir,
            .type_struct = type_struct,
            .final = final,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Interface = struct {
    name: []const u8,
    prerequisites: []const Prerequisite = &.{},
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    get_type: []const u8,
    type_struct: ?[]const u8 = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Interface) Function {
        return Function.forGetType(self, self.symbol_prefix, true);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Interface {
        var name: ?[]const u8 = null;
        var prerequisites = ArrayListUnmanaged(Prerequisite){};
        var functions = ArrayListUnmanaged(Function){};
        var constructors = ArrayListUnmanaged(Constructor){};
        var methods = ArrayListUnmanaged(Method){};
        var virtual_methods = ArrayListUnmanaged(VirtualMethod){};
        var signals = ArrayListUnmanaged(Signal){};
        var constants = ArrayListUnmanaged(Constant){};
        var get_type: ?[]const u8 = null;
        var type_struct: ?[]const u8 = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "type-struct")) {
                type_struct = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "prerequisite")) {
                    try prerequisites.append(allocator, try Prerequisite.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(allocator, try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(allocator, try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "virtual-method")) {
                    try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.glib, "signal")) {
                    try signals.append(allocator, try Signal.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(allocator, try Constant.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .prerequisites = try prerequisites.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .virtual_methods = try virtual_methods.toOwnedSlice(allocator),
            .signals = try signals.toOwnedSlice(allocator),
            .constants = try constants.toOwnedSlice(allocator),
            .get_type = get_type orelse return error.InvalidGir,
            .type_struct = type_struct,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Record = struct {
    name: []const u8,
    fields: []const Field,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    get_type: ?[]const u8 = null,
    disguised: bool = false,
    @"opaque": bool = false,
    pointer: bool = false,
    is_gtype_struct_for: ?[]const u8 = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Record) ?Function {
        return Function.forGetType(self, self.symbol_prefix, false);
    }

    pub fn isPointer(self: Record) bool {
        // The check on is_gtype_struct_for is a heuristic to avoid
        // mistranslations for class types (which are not typedefed pointers)
        return self.pointer or (self.disguised and !self.@"opaque" and self.is_gtype_struct_for == null);
    }

    pub fn isOpaque(self: Record) bool {
        return self.@"opaque" or (self.disguised and !self.pointer);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Record {
        var name: ?[]const u8 = null;
        var fields = ArrayListUnmanaged(Field){};
        var functions = ArrayListUnmanaged(Function){};
        var constructors = ArrayListUnmanaged(Constructor){};
        var methods = ArrayListUnmanaged(Method){};
        var get_type: ?[]const u8 = null;
        var disguised = false;
        var @"opaque" = false;
        var pointer = false;
        var is_gtype_struct_for: ?[]const u8 = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "disguised")) {
                disguised = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "opaque")) {
                @"opaque" = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "pointer")) {
                pointer = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(ns.glib, "is-gtype-struct-for")) {
                is_gtype_struct_for = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "field")) {
                    try fields.append(allocator, try Field.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(allocator, try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(allocator, try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .fields = try fields.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .get_type = get_type,
            .disguised = disguised,
            .@"opaque" = @"opaque",
            .pointer = pointer,
            .is_gtype_struct_for = is_gtype_struct_for,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Union = struct {
    name: []const u8,
    fields: []const Field,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    get_type: ?[]const u8 = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Union) ?Function {
        return Function.forGetType(self, self.symbol_prefix, false);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Union {
        var name: ?[]const u8 = null;
        var fields = ArrayListUnmanaged(Field){};
        var functions = ArrayListUnmanaged(Function){};
        var constructors = ArrayListUnmanaged(Constructor){};
        var methods = ArrayListUnmanaged(Method){};
        var get_type: ?[]const u8 = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "field")) {
                    try fields.append(allocator, try Field.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(allocator, try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(allocator, try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .fields = try fields.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .get_type = get_type,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Field = struct {
    name: []const u8,
    type: FieldType,
    // I haven't seen GIR go above 32 bits, but Zig supports up to u65535 😎
    bits: ?u16,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Field {
        var name: ?[]const u8 = null;
        var @"type": ?FieldType = null;
        var bits: ?u16 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "bits")) {
                bits = fmt.parseInt(u16, attr.value, 10) catch return error.InvalidGir;
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    @"type" = .{ .simple = try Type.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "array")) {
                    @"type" = .{ .array = try ArrayType.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "callback")) {
                    @"type" = .{ .callback = try Callback.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .type = @"type" orelse return error.InvalidGir,
            .bits = bits,
            .documentation = documentation,
        };
    }
};

pub const FieldType = union(enum) {
    simple: Type,
    array: ArrayType,
    callback: Callback,
};

pub const BitField = struct {
    name: []const u8,
    members: []const Member,
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: BitField) ?Function {
        return Function.forGetType(self, null, false);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !BitField {
        var name: ?[]const u8 = null;
        var members = ArrayListUnmanaged(Member){};
        var functions = ArrayListUnmanaged(Function){};
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "member")) {
                    try members.append(allocator, try Member.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .members = try members.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Enum = struct {
    name: []const u8,
    members: []const Member = &.{},
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Enum) ?Function {
        return Function.forGetType(self, null, false);
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Enum {
        var name: ?[]const u8 = null;
        var members = ArrayListUnmanaged(Member){};
        var functions = ArrayListUnmanaged(Function){};
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "member")) {
                    try members.append(allocator, try Member.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(allocator, try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .members = try members.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Member = struct {
    name: []const u8,
    value: i65, // big enough to hold an i32 or u64
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype) !Member {
        var name: ?[]const u8 = null;
        var value: ?i65 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "value")) {
                value = fmt.parseInt(i65, attr.value, 10) catch return error.InvalidGir;
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .value = value orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Function = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8 = null,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation = null,

    fn forGetType(elem: anytype, symbol_prefix: ?[]const u8, comptime required: bool) if (required) Function else ?Function {
        if (!required and elem.get_type == null) {
            return null;
        }

        const c_identifier = if (required) elem.get_type else elem.get_type.?;
        const name = if (symbol_prefix) |prefix| stripSymbolPrefix(c_identifier, prefix) else "get_type";

        return .{
            .name = name,
            .c_identifier = c_identifier,
            .parameters = &.{},
            .return_value = .{
                .nullable = false,
                .type = .{ .simple = .{
                    .name = .{ .ns = "GObject", .local = "Type" },
                    .c_type = "GType",
                } },
            },
        };
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Function {
        var name: ?[]const u8 = null;
        var c_identifier: ?[]const u8 = null;
        var moved_to: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.c, "identifier")) {
                c_identifier = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "moved-to")) {
                moved_to = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "throws")) {
                throws = mem.eql(u8, attr.value, "1");
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameters")) {
                    try Parameter.parseMany(allocator, &parameters, children.children(), current_ns);
                } else if (child.name.is(ns.core, "return-value")) {
                    return_value = try ReturnValue.parse(allocator, child, children.children(), current_ns);
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .c_identifier = c_identifier orelse return error.InvalidGir,
            .moved_to = moved_to,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .throws = throws,
            .documentation = documentation,
        };
    }
};

pub const Constructor = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8 = null,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Constructor {
        // Constructors currently have the same structure as functions
        const function = try Function.parse(allocator, start, children, current_ns);
        return .{
            .name = function.name,
            .c_identifier = function.c_identifier,
            .moved_to = function.moved_to,
            .parameters = function.parameters,
            .return_value = function.return_value,
            .throws = function.throws,
            .documentation = function.documentation,
        };
    }
};

pub const Method = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Method {
        // Methods currently have the same structure as functions
        const function = try Function.parse(allocator, start, children, current_ns);
        return .{
            .name = function.name,
            .c_identifier = function.c_identifier,
            .moved_to = function.moved_to,
            .parameters = function.parameters,
            .return_value = function.return_value,
            .throws = function.throws,
            .documentation = function.documentation,
        };
    }
};

pub const VirtualMethod = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !VirtualMethod {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "throws")) {
                throws = mem.eql(u8, attr.value, "1");
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameters")) {
                    try Parameter.parseMany(allocator, &parameters, children.children(), current_ns);
                } else if (child.name.is(ns.core, "return-value")) {
                    return_value = try ReturnValue.parse(allocator, child, children.children(), current_ns);
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .throws = throws,
            .documentation = documentation,
        };
    }
};

pub const Signal = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Signal {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameters")) {
                    try Parameter.parseMany(allocator, &parameters, children.children(), current_ns);
                } else if (child.name.is(ns.core, "return-value")) {
                    return_value = try ReturnValue.parse(allocator, child, children.children(), current_ns);
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Constant = struct {
    name: []const u8,
    value: []const u8,
    type: AnyType,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Constant {
        var name: ?[]const u8 = null;
        var value: ?[]const u8 = null;
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "value")) {
                value = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    @"type" = .{ .simple = try Type.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "array")) {
                    @"type" = .{ .array = try ArrayType.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .value = value orelse return error.InvalidGir,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const AnyType = union(enum) {
    simple: Type,
    array: ArrayType,
};

pub const Type = struct {
    name: ?Name = null,
    c_type: ?[]const u8 = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Type {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            }
        }

        try children.skip();

        return .{
            .name = name,
            .c_type = c_type,
        };
    }
};

pub const ArrayType = struct {
    name: ?Name = null,
    c_type: ?[]const u8 = null,
    element: *const AnyType,
    fixed_size: ?u32 = null,
    zero_terminated: bool = false,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !ArrayType {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var element: ?AnyType = null;
        var fixed_size: ?u32 = null;
        var zero_terminated = false;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "fixed-size")) {
                fixed_size = fmt.parseInt(u32, attr.value, 10) catch return error.InvalidGir;
            } else if (attr.name.is(null, "zero-terminated")) {
                zero_terminated = mem.eql(u8, attr.value, "1");
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    element = .{ .simple = try Type.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "array")) {
                    element = .{ .array = try ArrayType.parse(allocator, child, children.children(), current_ns) };
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .element = &(try allocator.dupe(AnyType, &.{element orelse return error.InvalidGir}))[0],
            .fixed_size = fixed_size,
            .zero_terminated = zero_terminated,
        };
    }
};

pub const Callback = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Callback {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "throws")) {
                throws = mem.eql(u8, attr.value, "1");
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameters")) {
                    try Parameter.parseMany(allocator, &parameters, children.children(), current_ns);
                } else if (child.name.is(ns.core, "return-value")) {
                    return_value = try ReturnValue.parse(allocator, child, children.children(), current_ns);
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .throws = throws,
            .documentation = documentation,
        };
    }
};

pub const Parameter = struct {
    name: []const u8,
    type: ParameterType,
    allow_none: bool = false,
    nullable: bool = false,
    optional: bool = false,
    instance: bool = false,
    closure: ?usize = null,
    destroy: ?usize = null,
    documentation: ?Documentation = null,

    pub fn isNullable(self: Parameter) bool {
        return self.allow_none or self.nullable or self.optional;
    }

    fn parseMany(allocator: Allocator, parameters: *ArrayListUnmanaged(Parameter), children: anytype, current_ns: []const u8) !void {
        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameter") or child.name.is(ns.core, "instance-parameter")) {
                    try parameters.append(allocator, try parse(allocator, child, children.children(), current_ns, child.name.is(ns.core, "instance-parameter")));
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8, instance: bool) !Parameter {
        var name: ?[]const u8 = null;
        var @"type": ?ParameterType = null;
        var allow_none = false;
        var nullable = false;
        var optional = false;
        var closure: ?usize = null;
        var destroy: ?usize = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "allow-none")) {
                allow_none = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "nullable")) {
                nullable = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "optional")) {
                optional = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "closure")) {
                closure = fmt.parseInt(usize, attr.value, 10) catch return error.InvalidGir;
            } else if (attr.name.is(null, "destroy")) {
                destroy = fmt.parseInt(usize, attr.value, 10) catch return error.InvalidGir;
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    @"type" = .{ .simple = try Type.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "array")) {
                    @"type" = .{ .array = try ArrayType.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "varargs")) {
                    @"type" = .varargs;
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .type = @"type" orelse return error.InvalidGir,
            .allow_none = allow_none,
            .nullable = nullable,
            .optional = optional,
            .instance = instance,
            .closure = closure,
            .destroy = destroy,
            .documentation = documentation,
        };
    }
};

pub const ParameterType = union(enum) {
    simple: Type,
    array: ArrayType,
    varargs,
};

pub const ReturnValue = struct {
    type: AnyType,
    allow_none: bool = false,
    nullable: bool = false,
    documentation: ?Documentation = null,

    pub fn isNullable(self: ReturnValue) bool {
        return self.allow_none or self.nullable;
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !ReturnValue {
        var @"type": ?AnyType = null;
        var allow_none = false;
        var nullable = false;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "allow-none")) {
                allow_none = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "nullable")) {
                nullable = mem.eql(u8, attr.value, "1");
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "type")) {
                    @"type" = .{ .simple = try Type.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "array")) {
                    @"type" = .{ .array = try ArrayType.parse(allocator, child, children.children(), current_ns) };
                } else if (child.name.is(ns.core, "doc")) {
                    documentation = try Documentation.parse(allocator, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .type = @"type" orelse return error.InvalidGir,
            .allow_none = allow_none,
            .nullable = nullable,
            .documentation = documentation,
        };
    }
};

pub const Implements = struct {
    name: Name,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Implements {
        var name: ?Name = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            }
        }

        try children.skip();

        return .{ .name = name orelse return error.InvalidGir };
    }
};

pub const Prerequisite = struct {
    name: Name,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Prerequisite {
        var name: ?Name = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            }
        }

        try children.skip();

        return .{ .name = name orelse return error.InvalidGir };
    }
};

pub const Documentation = struct {
    text: []const u8,

    fn parse(allocator: Allocator, children: anytype) !Documentation {
        var text = ArrayListUnmanaged(u8){};
        while (try children.next()) |event| {
            switch (event) {
                .element_content => |e| try text.appendSlice(allocator, e.content),
                else => {},
            }
        }
        return .{ .text = try text.toOwnedSlice(allocator) };
    }
};

// All the known built-in type names in GIR, which will be associated to the
// null namespace rather than the current namespace being translated. See also
// the map of builtin translations in translate.zig. This map contains fewer
// entries because it is only a set of GIR type names, not C type names.
const builtin_names = ComptimeStringMap(void, .{
    .{ "gboolean", {} },
    .{ "gchar", {} },
    .{ "guchar", {} },
    .{ "gint8", {} },
    .{ "guint8", {} },
    .{ "gint16", {} },
    .{ "guint16", {} },
    .{ "gint32", {} },
    .{ "guint32", {} },
    .{ "gint64", {} },
    .{ "guint64", {} },
    .{ "gshort", {} },
    .{ "gushort", {} },
    .{ "gint", {} },
    .{ "guint", {} },
    .{ "glong", {} },
    .{ "gulong", {} },
    .{ "gsize", {} },
    .{ "gssize", {} },
    .{ "gintptr", {} },
    .{ "guintptr", {} },
    .{ "gunichar2", {} },
    .{ "gunichar", {} },
    .{ "gfloat", {} },
    .{ "gdouble", {} },
    .{ "va_list", {} },
    .{ "none", {} },
    .{ "gpointer", {} },
    .{ "gconstpointer", {} },
    .{ "utf8", {} },
    .{ "filename", {} },
});

pub const Name = struct {
    ns: ?[]const u8,
    local: []const u8,

    fn parse(allocator: Allocator, raw: []const u8, current_ns: []const u8) !Name {
        const sep_pos = std.mem.indexOfScalar(u8, raw, '.');
        if (sep_pos) |pos| {
            return .{
                .ns = try allocator.dupe(u8, raw[0..pos]),
                .local = try allocator.dupe(u8, raw[pos + 1 .. raw.len]),
            };
        } else {
            return .{
                .ns = if (builtin_names.has(raw)) null else try allocator.dupe(u8, current_ns),
                .local = try allocator.dupe(u8, raw),
            };
        }
    }
};

fn stripSymbolPrefix(identifier: []const u8, symbol_prefix: []const u8) []const u8 {
    if (mem.indexOf(u8, identifier, symbol_prefix)) |index| {
        const stripped = identifier[index + symbol_prefix.len ..];
        return if (stripped.len > 0 and stripped[0] == '_') stripped[1..] else stripped;
    }
    return identifier;
}

test {
    testing.refAllDecls(@This());
}
