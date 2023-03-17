const std = @import("std");
const c = @import("c.zig");
const xml = @import("xml.zig");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

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

        var includes = ArrayList(Include).init(allocator);
        var packages = ArrayList(Package).init(allocator);
        var namespace: ?Namespace = null;

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "include")) {
                try includes.append(try Include.parse(allocator, doc, child));
            } else if (xml.nodeIs(child, ns.core, "package")) {
                try packages.append(try Package.parse(allocator, doc, child));
            } else if (xml.nodeIs(child, ns.core, "namespace")) {
                namespace = try Namespace.parse(allocator, doc, child);
            }
        }

        return .{
            .includes = includes.items,
            .packages = packages.items,
            .namespace = namespace orelse return error.InvalidGir,
            .arena = arena,
        };
    }
};

pub const Include = struct {
    name: []const u8,
    version: []const u8,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Include {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "version")) {
                version = try xml.attrContent(allocator, doc, attr);
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Package {
        var name: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Namespace {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var aliases = ArrayList(Alias).init(allocator);
        var classes = ArrayList(Class).init(allocator);
        var interfaces = ArrayList(Interface).init(allocator);
        var records = ArrayList(Record).init(allocator);
        var unions = ArrayList(Union).init(allocator);
        var bit_fields = ArrayList(BitField).init(allocator);
        var enums = ArrayList(Enum).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var callbacks = ArrayList(Callback).init(allocator);
        var constants = ArrayList(Constant).init(allocator);

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "version")) {
                version = try xml.attrContent(allocator, doc, attr);
            }
        }

        if (name == null) {
            return error.InvalidGir;
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "alias")) {
                try aliases.append(try Alias.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "class")) {
                try classes.append(try Class.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "interface")) {
                try interfaces.append(try Interface.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "record")) {
                try records.append(try Record.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "union")) {
                try unions.append(try Union.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "bitfield")) {
                try bit_fields.append(try BitField.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "enumeration")) {
                try enums.append(try Enum.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "callback")) {
                try callbacks.append(try Callback.parse(allocator, doc, child, name.?));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(try Constant.parse(allocator, doc, child, name.?));
            }
        }

        return .{
            .name = name.?,
            .version = version orelse return error.InvalidGir,
            .aliases = aliases.items,
            .classes = classes.items,
            .interfaces = interfaces.items,
            .records = records.items,
            .unions = unions.items,
            .bit_fields = bit_fields.items,
            .enums = enums.items,
            .functions = functions.items,
            .callbacks = callbacks.items,
            .constants = constants.items,
        };
    }
};

pub const Alias = struct {
    name: []const u8,
    type: Type,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Alias {
        var name: ?[]const u8 = null;
        var @"type": ?Type = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = try Type.parse(allocator, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
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
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Class) Function {
        return Function.forGetType(self, true);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Class {
        var name: ?[]const u8 = null;
        var parent: ?Name = null;
        var fields = ArrayList(Field).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var constructors = ArrayList(Constructor).init(allocator);
        var methods = ArrayList(Method).init(allocator);
        var virtual_methods = ArrayList(VirtualMethod).init(allocator);
        var signals = ArrayList(Signal).init(allocator);
        var constants = ArrayList(Constant).init(allocator);
        var get_type: ?[]const u8 = null;
        var type_struct: ?[]const u8 = null;
        var final = false;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "parent")) {
                parent = Name.parse(try xml.attrContent(allocator, doc, attr), current_ns);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "type-struct")) {
                type_struct = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "final")) {
                final = mem.eql(u8, try xml.attrContent(allocator, doc, attr), "1");
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(try Field.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(try Constructor.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(try Method.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "virtual-method")) {
                try virtual_methods.append(try VirtualMethod.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.glib, "signal")) {
                try signals.append(try Signal.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(try Constant.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parent = parent,
            .fields = fields.items,
            .functions = functions.items,
            .constructors = constructors.items,
            .methods = methods.items,
            .virtual_methods = virtual_methods.items,
            .signals = signals.items,
            .constants = constants.items,
            .get_type = get_type orelse return error.InvalidGir,
            .type_struct = type_struct,
            // For some reason, the final attribute is very rarely used. A more
            // reliable indicator seems to be the number of fields in the class (0
            // means it's final).
            .final = final or fields.items.len == 0,
            .documentation = documentation,
        };
    }
};

pub const Interface = struct {
    name: []const u8,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    get_type: []const u8,
    type_struct: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Interface) Function {
        return Function.forGetType(self, true);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Interface {
        var name: ?[]const u8 = null;
        var functions = ArrayList(Function).init(allocator);
        var constructors = ArrayList(Constructor).init(allocator);
        var methods = ArrayList(Method).init(allocator);
        var virtual_methods = ArrayList(VirtualMethod).init(allocator);
        var signals = ArrayList(Signal).init(allocator);
        var constants = ArrayList(Constant).init(allocator);
        var get_type: ?[]const u8 = null;
        var type_struct: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "type-struct")) {
                type_struct = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(try Constructor.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(try Method.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "virtual-method")) {
                try virtual_methods.append(try VirtualMethod.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.glib, "signal")) {
                try signals.append(try Signal.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constant")) {
                try constants.append(try Constant.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .functions = functions.items,
            .constructors = constructors.items,
            .methods = methods.items,
            .virtual_methods = virtual_methods.items,
            .signals = signals.items,
            .constants = constants.items,
            .get_type = get_type orelse return error.InvalidGir,
            .type_struct = type_struct,
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
    is_gtype_struct_for: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Record) ?Function {
        return Function.forGetType(self, false);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Record {
        var name: ?[]const u8 = null;
        var fields = ArrayList(Field).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var constructors = ArrayList(Constructor).init(allocator);
        var methods = ArrayList(Method).init(allocator);
        var get_type: ?[]const u8 = null;
        var is_gtype_struct_for: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "is-gtype-struct-for")) {
                is_gtype_struct_for = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(try Field.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(try Constructor.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(try Method.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .fields = fields.items,
            .functions = functions.items,
            .constructors = constructors.items,
            .methods = methods.items,
            .get_type = get_type,
            .is_gtype_struct_for = is_gtype_struct_for,
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
    documentation: ?Documentation = null,

    pub fn getTypeFunction(self: Union) ?Function {
        return Function.forGetType(self, false);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Union {
        var name: ?[]const u8 = null;
        var fields = ArrayList(Field).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var constructors = ArrayList(Constructor).init(allocator);
        var methods = ArrayList(Method).init(allocator);
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "field")) {
                try fields.append(try Field.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "constructor")) {
                try constructors.append(try Constructor.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "method")) {
                try methods.append(try Method.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .fields = fields.items,
            .functions = functions.items,
            .constructors = constructors.items,
            .methods = methods.items,
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Field = struct {
    name: []const u8,
    type: FieldType,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Field {
        var name: ?[]const u8 = null;
        var @"type": ?FieldType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "callback")) {
                @"type" = .{ .callback = try Callback.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
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
        return Function.forGetType(self, false);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !BitField {
        var name: ?[]const u8 = null;
        var members = ArrayList(Member).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "member")) {
                try members.append(try Member.parse(allocator, doc, child));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .members = members.items,
            .functions = functions.items,
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
        return Function.forGetType(self, false);
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Enum {
        var name: ?[]const u8 = null;
        var members = ArrayList(Member).init(allocator);
        var functions = ArrayList(Function).init(allocator);
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.glib, "get-type")) {
                get_type = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "member")) {
                try members.append(try Member.parse(allocator, doc, child));
            } else if (xml.nodeIs(child, ns.core, "function")) {
                try functions.append(try Function.parse(allocator, doc, child, current_ns));
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .members = members.items,
            .functions = functions.items,
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Member = struct {
    name: []const u8,
    value: i64,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Member {
        var name: ?[]const u8 = null;
        var value: ?i64 = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "value")) {
                value = fmt.parseInt(i64, try xml.attrContent(allocator, doc, attr), 10) catch return error.InvalidGir;
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
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
    documentation: ?Documentation = null,

    fn forGetType(elem: anytype, comptime required: bool) if (required) Function else ?Function {
        if (!required and elem.get_type == null) {
            return null;
        }

        const get_type = if (required) elem.get_type else elem.get_type.?;

        return .{
            .name = "get_type",
            .c_identifier = get_type,
            .moved_to = null,
            .parameters = &.{},
            .return_value = .{
                .nullable = false,
                .type = .{ .simple = .{
                    .name = .{ .ns = "GObject", .local = "Type" },
                    .c_type = "GType",
                } },
                .documentation = null,
            },
            .documentation = null,
        };
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Function {
        var name: ?[]const u8 = null;
        var c_identifier: ?[]const u8 = null;
        var moved_to: ?[]const u8 = null;
        var parameters = ArrayList(Parameter).init(allocator);
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, ns.c, "identifier")) {
                c_identifier = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "moved-to")) {
                moved_to = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "documentation")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .c_identifier = c_identifier orelse return error.InvalidGir,
            .moved_to = moved_to,
            .parameters = parameters.items,
            .return_value = return_value orelse return error.InvalidGir,
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
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Constructor {
        // Constructors currently have the same structure as functions
        const function = try Function.parse(allocator, doc, node, current_ns);
        return .{
            .name = function.name,
            .c_identifier = function.c_identifier,
            .moved_to = function.moved_to,
            .parameters = function.parameters,
            .return_value = function.return_value,
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
    documentation: ?Documentation,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Method {
        // Methods currently have the same structure as functions
        const function = try Function.parse(allocator, doc, node, current_ns);
        return .{
            .name = function.name,
            .c_identifier = function.c_identifier,
            .moved_to = function.moved_to,
            .parameters = function.parameters,
            .return_value = function.return_value,
            .documentation = function.documentation,
        };
    }
};

pub const VirtualMethod = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !VirtualMethod {
        var name: ?[]const u8 = null;
        var parameters = ArrayList(Parameter).init(allocator);
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = parameters.items,
            .return_value = return_value orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Signal = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Signal {
        var name: ?[]const u8 = null;
        var parameters = ArrayList(Parameter).init(allocator);
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = parameters.items,
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Constant {
        var name: ?[]const u8 = null;
        var value: ?[]const u8 = null;
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "value")) {
                value = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Type {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = Name.parse(try xml.attrContent(allocator, doc, attr), current_ns);
            } else if (xml.attrIs(attr, ns.c, "type")) {
                c_type = try xml.attrContent(allocator, doc, attr);
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !ArrayType {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var element: ?AnyType = null;
        var fixed_size: ?u32 = null;
        var zero_terminated = false;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = Name.parse(try xml.attrContent(allocator, doc, attr), current_ns);
            } else if (xml.attrIs(attr, ns.c, "type")) {
                c_type = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "fixed-size")) {
                const content = try xml.attrContent(allocator, doc, attr);
                fixed_size = fmt.parseInt(u32, content, 10) catch return error.InvalidGir;
            } else if (xml.attrIs(attr, null, "zero-terminated")) {
                zero_terminated = mem.eql(u8, try xml.attrContent(allocator, doc, attr), "1");
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                element = .{ .simple = try Type.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                element = .{ .array = try ArrayType.parse(allocator, doc, child, current_ns) };
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
    documentation: ?Documentation,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !Callback {
        var name: ?[]const u8 = null;
        var parameters = ArrayList(Parameter).init(allocator);
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "parameters")) {
                try Parameter.parseMany(allocator, &parameters, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "return-value")) {
                return_value = try ReturnValue.parse(allocator, doc, child, current_ns);
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .parameters = parameters.items,
            .return_value = return_value orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Parameter = struct {
    name: []const u8,
    nullable: bool = false,
    type: ParameterType,
    instance: bool = false,
    documentation: ?Documentation = null,

    fn parseMany(allocator: Allocator, parameters: *ArrayList(Parameter), doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !void {
        var maybe_param: ?*c.xmlNode = node.children;
        while (maybe_param) |param| : (maybe_param = param.next) {
            if (xml.nodeIs(param, ns.core, "parameter") or xml.nodeIs(param, ns.core, "instance-parameter")) {
                try parameters.append(try parse(allocator, doc, param, current_ns, xml.nodeIs(param, ns.core, "instance-parameter")));
            }
        }
    }

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8, instance: bool) !Parameter {
        var name: ?[]const u8 = null;
        var nullable = false;
        var @"type": ?ParameterType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "name")) {
                name = try xml.attrContent(allocator, doc, attr);
            } else if (xml.attrIs(attr, null, "nullable")) {
                nullable = mem.eql(u8, try xml.attrContent(allocator, doc, attr), "1");
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "varargs")) {
                @"type" = .{ .varargs = {} };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, child);
            }
        }

        return .{
            .name = name orelse return error.InvalidGir,
            .nullable = nullable,
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

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, current_ns: []const u8) !ReturnValue {
        var nullable = false;
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        var maybe_attr: ?*c.xmlAttr = node.properties;
        while (maybe_attr) |attr| : (maybe_attr = attr.next) {
            if (xml.attrIs(attr, null, "nullable")) {
                nullable = mem.eql(u8, try xml.attrContent(allocator, doc, attr), "1");
            }
        }

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns.core, "type")) {
                @"type" = .{ .simple = try Type.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "array")) {
                @"type" = .{ .array = try ArrayType.parse(allocator, doc, child, current_ns) };
            } else if (xml.nodeIs(child, ns.core, "doc")) {
                documentation = try Documentation.parse(allocator, doc, node);
            }
        }

        return .{
            .nullable = nullable,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Documentation = struct {
    text: []const u8,

    fn parse(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Documentation {
        return .{ .text = try xml.nodeContent(allocator, doc, node.children) };
    }
};

pub const Name = struct {
    ns: ?[]const u8,
    local: []const u8,

    fn parse(raw: []const u8, current_ns: []const u8) Name {
        const sep_pos = std.mem.indexOfScalar(u8, raw, '.');
        if (sep_pos) |pos| {
            return .{
                .ns = raw[0..pos],
                .local = raw[pos + 1 .. raw.len],
            };
        } else {
            // There isn't really any way to distinguish between a name in the same
            // namespace and a non-namespaced name: based on convention, though, we can
            // use the heuristic of looking for an uppercase starting letter
            return .{
                .ns = if (raw.len > 0 and std.ascii.isUpper(raw[0])) current_ns else null,
                .local = raw,
            };
        }
    }
};

test {
    testing.refAllDecls(@This());
}
