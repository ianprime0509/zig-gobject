const std = @import("std");
const c = @import("c.zig");
const xml = @import("xml.zig");
const fmt = std.fmt;
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

    pub fn parseFile(allocator: Allocator, file: [:0]const u8) Error!Repository {
        const doc = xml.parseFile(file) catch return error.InvalidGir;
        defer c.xmlFreeDoc(doc);
        return try parseDoc(allocator, doc);
    }

    pub fn deinit(self: *Repository) void {
        self.arena.deinit();
    }

    fn parseDoc(a: Allocator, doc: *c.xmlDoc) !Repository {
        var arena = ArenaAllocator.init(a);
        const allocator = arena.allocator();
        const node: *c.xmlNode = c.xmlDocGetRootElement(doc) orelse return error.InvalidGir;

        var includes = ArrayListUnmanaged(Include){};
        var packages = ArrayListUnmanaged(Package){};
        var namespace: ?Namespace = null;

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "include")) {
                try includes.append(allocator, try Include.parse(allocator, child));
            } else if (xml.nodeIs(child, ns.core, "package")) {
                try packages.append(allocator, try Package.parse(allocator, child));
            } else if (xml.nodeIs(child, ns.core, "namespace")) {
                namespace = try Namespace.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode) !Include {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "version")) {
                version = try xml.attrContent(allocator, attr);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .version = version orelse return error.InvalidGir,
        };
    }
};

pub const Package = struct {
    name: []const u8,

    fn parse(allocator: Allocator, node: *const c.xmlNode) !Package {
        var name: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            }
        }

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

    fn parse(allocator: Allocator, node: *const c.xmlNode) !Namespace {
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

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "version")) {
                version = try xml.attrContent(allocator, attr);
            }
        }

        if (name == null) {
            return error.InvalidGir;
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "alias")) {
                try aliases.append(allocator, try Alias.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "class")) {
                try classes.append(allocator, try Class.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "interface")) {
                try interfaces.append(allocator, try Interface.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "record")) {
                try records.append(allocator, try Record.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "union")) {
                try unions.append(allocator, try Union.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "bitfield")) {
                try bit_fields.append(allocator, try BitField.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "enumeration")) {
                try enums.append(allocator, try Enum.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "callback")) {
                try callbacks.append(allocator, try Callback.parse(allocator, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(allocator, try Constant.parse(allocator, child, name.?));
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Alias {
        var name: ?[]const u8 = null;
        var @"type": ?Type = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = try Type.parse(allocator, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Class {
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

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "parent")) {
                parent = try Name.parse(allocator, attr, current_ns);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "type-struct")) {
                type_struct = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "final")) {
                final = try xml.attrContentBool(allocator, attr);
            } else if (xml.attrIs(attr, ns.c, "symbol-prefix")) {
                symbol_prefix = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "implements")) {
                try implements.append(allocator, try Implements.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(allocator, try Field.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(allocator, try Constructor.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(allocator, try Method.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "virtual-method")) {
                try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.glib, "signal")) {
                try signals.append(allocator, try Signal.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(allocator, try Constant.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Interface {
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

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "type-struct")) {
                type_struct = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.c, "symbol-prefix")) {
                symbol_prefix = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "prerequisite")) {
                try prerequisites.append(allocator, try Prerequisite.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(allocator, try Constructor.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(allocator, try Method.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "virtual-method")) {
                try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.glib, "signal")) {
                try signals.append(allocator, try Signal.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(allocator, try Constant.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Record {
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

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "disguised")) {
                disguised = try xml.attrContentBool(allocator, attr);
            } else if (xml.attrIs(attr, null, "opaque")) {
                @"opaque" = try xml.attrContentBool(allocator, attr);
            } else if (xml.attrIs(attr, null, "pointer")) {
                pointer = try xml.attrContentBool(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "is-gtype-struct-for")) {
                is_gtype_struct_for = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.c, "symbol-prefix")) {
                symbol_prefix = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(allocator, try Field.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(allocator, try Constructor.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(allocator, try Method.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Union {
        var name: ?[]const u8 = null;
        var fields = ArrayListUnmanaged(Field){};
        var functions = ArrayListUnmanaged(Function){};
        var constructors = ArrayListUnmanaged(Constructor){};
        var methods = ArrayListUnmanaged(Method){};
        var get_type: ?[]const u8 = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.c, "symbol-prefix")) {
                symbol_prefix = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(allocator, try Field.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(allocator, try Constructor.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(allocator, try Method.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Field {
        var name: ?[]const u8 = null;
        var @"type": ?FieldType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "callback")) {
                @"type" = .{ .callback = try Callback.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .type = @"type" orelse return error.InvalidGir,
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !BitField {
        var name: ?[]const u8 = null;
        var members = ArrayListUnmanaged(Member){};
        var functions = ArrayListUnmanaged(Function){};
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "member")) {
                try members.append(allocator, try Member.parse(allocator, child));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Enum {
        var name: ?[]const u8 = null;
        var members = ArrayListUnmanaged(Member){};
        var functions = ArrayListUnmanaged(Function){};
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "member")) {
                try members.append(allocator, try Member.parse(allocator, child));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(allocator, try Function.parse(allocator, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode) !Member {
        var name: ?[]const u8 = null;
        var value: ?i65 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "value")) {
                value = fmt.parseInt(i65, try xml.attrContent(allocator, attr), 10) catch return error.InvalidGir;
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Function {
        var name: ?[]const u8 = null;
        var c_identifier: ?[]const u8 = null;
        var moved_to: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, ns.c, "identifier")) {
                c_identifier = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "moved-to")) {
                moved_to = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "throws")) {
                throws = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "documentation")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Constructor {
        // Constructors currently have the same structure as functions
        const function = try Function.parse(allocator, node, current_ns);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Method {
        // Methods currently have the same structure as functions
        const function = try Function.parse(allocator, node, current_ns);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !VirtualMethod {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "throws")) {
                throws = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Signal {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Constant {
        var name: ?[]const u8 = null;
        var value: ?[]const u8 = null;
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "value")) {
                value = try xml.attrContent(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Type {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try Name.parse(allocator, attr, current_ns);
            } else if (xml.attrIs(attr, ns.c, "type")) {
                c_type = try xml.attrContent(allocator, attr);
            }
        }

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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !ArrayType {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var element: ?AnyType = null;
        var fixed_size: ?u32 = null;
        var zero_terminated = false;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try Name.parse(allocator, attr, current_ns);
            } else if (xml.attrIs(attr, ns.c, "type")) {
                c_type = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "fixed-size")) {
                const content = try xml.attrContent(allocator, attr);
                fixed_size = fmt.parseInt(u32, content, 10) catch return error.InvalidGir;
            } else if (xml.attrIs(attr, null, "zero-terminated")) {
                zero_terminated = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                element = .{ .simple = try Type.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                element = .{ .array = try ArrayType.parse(allocator, child, current_ns) };
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

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Callback {
        var name: ?[]const u8 = null;
        var parameters = ArrayListUnmanaged(Parameter){};
        var return_value: ?ReturnValue = null;
        var throws = false;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "throws")) {
                throws = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
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
    nullable: bool = false,
    optional: bool = false,
    type: ParameterType,
    instance: bool = false,
    documentation: ?Documentation = null,

    fn parseMany(allocator: Allocator, parameters: *ArrayListUnmanaged(Parameter), node: *const c.xmlNode, current_ns: []const u8) !void {
        var maybe_param: ?*c.xmlNode = node.children;
        while (maybe_param) |param| : (maybe_param = param.next) {
            if (xml.nodeIs(param, ns.core, "parameter") or xml.nodeIs(param, ns.core, "instance-parameter")) {
                try parameters.append(allocator, try parse(allocator, param, current_ns, xml.nodeIs(param, ns.core, "instance-parameter")));
            }
        }
    }

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8, instance: bool) !Parameter {
        var name: ?[]const u8 = null;
        var nullable = false;
        var optional = false;
        var @"type": ?ParameterType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, attr);
            } else if (xml.attrIs(attr, null, "nullable")) {
                nullable = try xml.attrContentBool(allocator, attr);
            } else if (xml.attrIs(attr, null, "optional")) {
                optional = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "varargs")) {
                @"type" = .{ .varargs = {} };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .nullable = nullable,
            .optional = optional,
            .type = @"type" orelse return error.InvalidGir,
            .instance = instance,
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
    nullable: bool = false,
    type: AnyType,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !ReturnValue {
        var nullable = false;
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "nullable")) {
                nullable = try xml.attrContentBool(allocator, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, node);
            }
        }

        return .{
            .nullable = nullable,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Implements = struct {
    name: Name,

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Implements {
        var name: ?Name = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try Name.parse(allocator, attr, current_ns);
            }
        }

        return .{ .name = name orelse return error.InvalidGir };
    }
};

pub const Prerequisite = struct {
    name: Name,

    fn parse(allocator: Allocator, node: *const c.xmlNode, current_ns: []const u8) !Prerequisite {
        var name: ?Name = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try Name.parse(allocator, attr, current_ns);
            }
        }

        return .{ .name = name orelse return error.InvalidGir };
    }
};

pub const Documentation = struct {
    text: []const u8,

    fn parse(allocator: Allocator, node: *const c.xmlNode) !Documentation {
        return .{ .text = try xml.nodeContent(allocator, node) };
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
    // Only int32 has been observed in the wild so far (in freetype-2.0); the
    // others are extrapolated
    .{ "int8", {} },
    .{ "uint8", {} },
    .{ "int16", {} },
    .{ "uint16", {} },
    .{ "int32", {} },
    .{ "uint32", {} },
    .{ "int64", {} },
    .{ "uint64", {} },
});

pub const Name = struct {
    ns: ?[]const u8,
    local: []const u8,

    fn parse(allocator: Allocator, attr: *const c.xmlAttr, current_ns: []const u8) !Name {
        const raw = try xml.attrContent(allocator, attr);
        defer allocator.free(raw);
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
