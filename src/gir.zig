const std = @import("std");
const c = @import("c.zig");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const ns = struct {
    pub const core = "http://www.gtk.org/introspection/core/1.0";
    pub const c = "http://www.gtk.org/introspection/c/1.0";
    pub const glib = "http://www.gtk.org/introspection/glib/1.0";
};

pub const Repository = struct {
    includes: []const Include,
    namespaces: []const Namespace,
    arena: ArenaAllocator,

    pub fn parseFile(allocator: Allocator, file: [:0]const u8) !Repository {
        const doc = c.xmlParseFile(@ptrCast([*c]const u8, file)) orelse return error.InvalidGir;
        defer c.xmlFreeDoc(doc);
        return try parseDoc(allocator, doc);
    }

    fn parseDoc(a: Allocator, doc: *c.xmlDoc) !Repository {
        var arena = ArenaAllocator.init(a);
        const allocator = arena.allocator();
        const node: *c.xmlNode = c.xmlDocGetRootElement(doc) orelse return error.InvalidGir;

        var includes = ArrayList(Include).init(allocator);
        var namespaces = ArrayList(Namespace).init(allocator);

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (nodeIs(child, ns.core, "include")) {
                try includes.append(try parseInclude(allocator, doc, child));
            } else if (nodeIs(child, ns.core, "namespace")) {
                try namespaces.append(try parseNamespace(allocator, doc, child));
            }
        }

        return .{
            .includes = includes.items,
            .namespaces = namespaces.items,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Repository) void {
        self.arena.deinit();
    }
};

pub const Include = struct {
    name: []const u8,
    version: []const u8,
};

fn parseInclude(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Include {
    var name: ?[]const u8 = null;
    var version: ?[]const u8 = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, null, "version")) {
            version = try attrContent(allocator, doc, attr);
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .version = version orelse return error.InvalidGir,
    };
}

pub const Namespace = struct {
    name: []const u8,
    aliases: []const Alias,
    classes: []const Class,
    interfaces: []const Interface,
    records: []const Record,
    unions: []const Union,
    bit_fields: []const BitField,
    enums: []const Enum,
    functions: []const Function,
    callbacks: []const Callback,
};

fn parseNamespace(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Namespace {
    var name: ?[]const u8 = null;
    var aliases = ArrayList(Alias).init(allocator);
    var classes = ArrayList(Class).init(allocator);
    var interfaces = ArrayList(Interface).init(allocator);
    var records = ArrayList(Record).init(allocator);
    var unions = ArrayList(Union).init(allocator);
    var bit_fields = ArrayList(BitField).init(allocator);
    var enums = ArrayList(Enum).init(allocator);
    var functions = ArrayList(Function).init(allocator);
    var callbacks = ArrayList(Callback).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "alias")) {
            try aliases.append(try parseAlias(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "class")) {
            try classes.append(try parseClass(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "interface")) {
            try interfaces.append(try parseInterface(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "record")) {
            try records.append(try parseRecord(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "union")) {
            try unions.append(try parseUnion(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "bitfield")) {
            try bit_fields.append(try parseBitField(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "enumeration")) {
            try enums.append(try parseEnum(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "callback")) {
            try callbacks.append(try parseCallback(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .aliases = aliases.items,
        .classes = classes.items,
        .interfaces = interfaces.items,
        .records = records.items,
        .unions = unions.items,
        .bit_fields = bit_fields.items,
        .enums = enums.items,
        .functions = functions.items,
        .callbacks = callbacks.items,
    };
}

pub const Alias = struct {
    name: []const u8,
    type: Type,
};

fn parseAlias(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Alias {
    var name: ?[]const u8 = null;
    var @"type": ?Type = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "type")) {
            @"type" = try parseType(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .type = @"type" orelse return error.InvalidGir,
    };
}

pub const Class = struct {
    name: []const u8,
    parent: ?Name,
    fields: []const Field,
    functions: []const Function,
    constructors: []const Constructor,
    methods: []const Method,
};

fn parseClass(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Class {
    var name: ?[]const u8 = null;
    var parent: ?Name = null;
    var fields = ArrayList(Field).init(allocator);
    var functions = ArrayList(Function).init(allocator);
    var constructors = ArrayList(Constructor).init(allocator);
    var methods = ArrayList(Method).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, null, "parent")) {
            parent = parseName(try attrContent(allocator, doc, attr));
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "field")) {
            try fields.append(try parseField(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "constructor")) {
            try constructors.append(try parseConstructor(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "method")) {
            try methods.append(try parseMethod(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .parent = parent,
        .fields = fields.items,
        .functions = functions.items,
        .constructors = constructors.items,
        .methods = methods.items,
    };
}

pub const Interface = struct {
    name: []const u8,
    functions: []const Function,
    constructors: []const Constructor,
    methods: []const Method,
};

fn parseInterface(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Interface {
    var name: ?[]const u8 = null;
    var functions = ArrayList(Function).init(allocator);
    var constructors = ArrayList(Constructor).init(allocator);
    var methods = ArrayList(Method).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "constructor")) {
            try constructors.append(try parseConstructor(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "method")) {
            try methods.append(try parseMethod(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .functions = functions.items,
        .constructors = constructors.items,
        .methods = methods.items,
    };
}

pub const Record = struct {
    name: []const u8,
    fields: []const Field,
    functions: []const Function,
    constructors: []const Constructor,
    methods: []const Method,
};

fn parseRecord(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Record {
    var name: ?[]const u8 = null;
    var fields = ArrayList(Field).init(allocator);
    var functions = ArrayList(Function).init(allocator);
    var constructors = ArrayList(Constructor).init(allocator);
    var methods = ArrayList(Method).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "field")) {
            try fields.append(try parseField(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "constructor")) {
            try constructors.append(try parseConstructor(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "method")) {
            try methods.append(try parseMethod(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .fields = fields.items,
        .functions = functions.items,
        .constructors = constructors.items,
        .methods = methods.items,
    };
}

pub const Union = struct {
    name: []const u8,
    fields: []const Field,
    functions: []const Function,
    constructors: []const Constructor,
    methods: []const Method,
};

fn parseUnion(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Union {
    var name: ?[]const u8 = null;
    var fields = ArrayList(Field).init(allocator);
    var functions = ArrayList(Function).init(allocator);
    var constructors = ArrayList(Constructor).init(allocator);
    var methods = ArrayList(Method).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "field")) {
            try fields.append(try parseField(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "constructor")) {
            try constructors.append(try parseConstructor(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "method")) {
            try methods.append(try parseMethod(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .fields = fields.items,
        .functions = functions.items,
        .constructors = constructors.items,
        .methods = methods.items,
    };
}

pub const Field = struct {
    name: []const u8,
    type: FieldType,
};

pub const FieldType = union(enum) {
    simple: Type,
    array: ArrayType,
    callback: Callback,
};

fn parseField(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Field {
    var name: ?[]const u8 = null;
    var @"type": ?FieldType = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "type")) {
            @"type" = .{ .simple = try parseType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "array")) {
            @"type" = .{ .array = try parseArrayType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "callback")) {
            @"type" = .{ .callback = try parseCallback(allocator, doc, child) };
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .type = @"type" orelse return error.InvalidGir,
    };
}

pub const BitField = struct {
    name: []const u8,
    members: []const Member,
    functions: []const Function,
};

fn parseBitField(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !BitField {
    var name: ?[]const u8 = null;
    var members = ArrayList(Member).init(allocator);
    var functions = ArrayList(Function).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "member")) {
            try members.append(try parseMember(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .members = members.items,
        .functions = functions.items,
    };
}

pub const Enum = struct {
    name: []const u8,
    members: []const Member,
    functions: []const Function,
};

fn parseEnum(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Enum {
    var name: ?[]const u8 = null;
    var members = ArrayList(Member).init(allocator);
    var functions = ArrayList(Function).init(allocator);

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "member")) {
            try members.append(try parseMember(allocator, doc, child));
        } else if (nodeIs(child, ns.core, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .members = members.items,
        .functions = functions.items,
    };
}

pub const Member = struct {
    name: []const u8,
    value: i64,
};

fn parseMember(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Member {
    var name: ?[]const u8 = null;
    var value: ?i64 = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, null, "value")) {
            value = fmt.parseInt(i64, try attrContent(allocator, doc, attr), 10) catch return error.InvalidGir;
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .value = value orelse return error.InvalidGir,
    };
}

pub const Function = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
};

fn parseFunction(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Function {
    var name: ?[]const u8 = null;
    var c_identifier: ?[]const u8 = null;
    var moved_to: ?[]const u8 = null;
    var parameters = ArrayList(Parameter).init(allocator);
    var return_value: ?ReturnValue = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, ns.c, "identifier")) {
            c_identifier = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, null, "moved-to")) {
            moved_to = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "parameters")) {
            try parseParameters(allocator, &parameters, doc, child);
        } else if (nodeIs(child, ns.core, "return-value")) {
            return_value = try parseReturnValue(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .c_identifier = c_identifier orelse return error.InvalidGir,
        .moved_to = moved_to,
        .parameters = parameters.items,
        .return_value = return_value orelse return error.InvalidGir,
    };
}

pub const Constructor = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
};

fn parseConstructor(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Constructor {
    // Constructors currently have the same structure as functions
    const function = try parseFunction(allocator, doc, node);
    return .{
        .name = function.name,
        .c_identifier = function.c_identifier,
        .moved_to = function.moved_to,
        .parameters = function.parameters,
        .return_value = function.return_value,
    };
}

pub const Method = struct {
    name: []const u8,
    c_identifier: []const u8,
    moved_to: ?[]const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
};

fn parseMethod(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Method {
    // Methods currently have the same structure as functions
    const function = try parseFunction(allocator, doc, node);
    return .{
        .name = function.name,
        .c_identifier = function.c_identifier,
        .moved_to = function.moved_to,
        .parameters = function.parameters,
        .return_value = function.return_value,
    };
}

pub const AnyType = union(enum) {
    simple: Type,
    array: ArrayType,
};

pub const Type = struct {
    name: ?Name,
    c_type: ?[]const u8,
};

fn parseType(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Type {
    var name: ?[]const u8 = null;
    var c_type: ?[]const u8 = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, ns.c, "type")) {
            c_type = try attrContent(allocator, doc, attr);
        }
    }

    const parsed_name = blk: {
        if (name) |n| {
            break :blk parseName(n);
        } else {
            break :blk null;
        }
    };

    return .{
        .name = parsed_name,
        .c_type = c_type,
    };
}

pub const ArrayType = struct {
    element: *const AnyType,
    fixed_size: ?u32,
};

fn parseArrayType(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !ArrayType {
    var element: ?AnyType = null;
    var fixed_size: ?[]const u8 = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "fixed-size")) {
            fixed_size = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "type")) {
            element = .{ .simple = try parseType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "array")) {
            element = .{ .array = try parseArrayType(allocator, doc, child) };
        }
    }

    return .{
        .element = &(try allocator.dupe(AnyType, &.{element orelse return error.InvalidGir}))[0],
        .fixed_size = size: {
            if (fixed_size) |size| {
                break :size fmt.parseInt(u32, size, 10) catch return error.InvalidGir;
            } else {
                break :size null;
            }
        },
    };
}

pub const Callback = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
};

fn parseCallback(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Callback {
    var name: ?[]const u8 = null;
    var parameters = ArrayList(Parameter).init(allocator);
    var return_value: ?ReturnValue = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "parameters")) {
            try parseParameters(allocator, &parameters, doc, child);
        } else if (nodeIs(child, ns.core, "return-value")) {
            return_value = try parseReturnValue(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .parameters = parameters.items,
        .return_value = return_value orelse return error.InvalidGir,
    };
}

pub const Parameter = struct {
    name: []const u8,
    nullable: bool,
    type: ParameterType,
    instance: bool,
};

pub const ParameterType = union(enum) {
    simple: Type,
    array: ArrayType,
    varargs,
};

fn parseParameters(allocator: Allocator, parameters: *ArrayList(Parameter), doc: *c.xmlDoc, node: *const c.xmlNode) !void {
    var maybe_param: ?*c.xmlNode = node.children;
    while (maybe_param) |param| : (maybe_param = param.next) {
        if (nodeIs(param, ns.core, "parameter") or nodeIs(param, ns.core, "instance-parameter")) {
            try parameters.append(try parseParameter(allocator, doc, param, nodeIs(param, ns.core, "instance-parameter")));
        }
    }
}

fn parseParameter(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode, instance: bool) !Parameter {
    var name: ?[]const u8 = null;
    var nullable = false;
    var @"type": ?ParameterType = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "name")) {
            name = try attrContent(allocator, doc, attr);
        } else if (attrIs(attr, null, "nullable")) {
            nullable = mem.eql(u8, try attrContent(allocator, doc, attr), "1");
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "type")) {
            @"type" = .{ .simple = try parseType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "array")) {
            @"type" = .{ .array = try parseArrayType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "varargs")) {
            @"type" = .{ .varargs = {} };
        }
    }

    return .{
        .name = name orelse return error.InvalidGir,
        .nullable = nullable,
        .type = @"type" orelse return error.InvalidGir,
        .instance = instance,
    };
}

pub const ReturnValue = struct {
    nullable: bool,
    type: AnyType,
};

fn parseReturnValue(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !ReturnValue {
    var nullable = false;
    var @"type": ?AnyType = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (attrIs(attr, null, "nullable")) {
            nullable = mem.eql(u8, try attrContent(allocator, doc, attr), "1");
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (nodeIs(child, ns.core, "type")) {
            @"type" = .{ .simple = try parseType(allocator, doc, child) };
        } else if (nodeIs(child, ns.core, "array")) {
            @"type" = .{ .array = try parseArrayType(allocator, doc, child) };
        }
    }

    return .{
        .nullable = nullable,
        .type = @"type" orelse return error.InvalidGir,
    };
}

pub const Name = struct {
    ns: ?[]const u8,
    local: []const u8,
};

fn parseName(raw: []const u8) Name {
    const sep_pos = std.mem.indexOfScalar(u8, raw, '.');
    if (sep_pos) |pos| {
        return .{
            .ns = raw[0..pos],
            .local = raw[pos + 1 .. raw.len],
        };
    } else {
        return .{
            .ns = null,
            .local = raw,
        };
    }
}

fn nodeIs(node: *const c.xmlNode, ns_name: ?[:0]const u8, local_name: [:0]const u8) bool {
    if (!std.mem.eql(u8, local_name, std.mem.sliceTo(node.name, 0))) {
        return false;
    }
    if (ns_name) |n| {
        return node.ns != null and std.mem.eql(u8, n, std.mem.sliceTo(node.ns.*.href, 0));
    } else {
        return node.ns == null;
    }
}

fn nodeContent(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) ![]u8 {
    const content = c.xmlNodeListGetString(doc, node, 1);
    defer xmlFree(content);
    if (content) |str| {
        return try allocator.dupe(u8, std.mem.sliceTo(str, 0));
    } else {
        return try allocator.dupe(u8, "");
    }
}

fn attrIs(attr: *const c.xmlAttr, ns_name: ?[:0]const u8, local_name: [:0]const u8) bool {
    if (!std.mem.eql(u8, local_name, std.mem.sliceTo(attr.name, 0))) {
        return false;
    }
    if (ns_name) |n| {
        return attr.ns != null and std.mem.eql(u8, n, std.mem.sliceTo(attr.ns.*.href, 0));
    } else {
        return attr.ns == null;
    }
}

fn attrContent(allocator: Allocator, doc: *c.xmlDoc, attr: *const c.xmlAttr) ![]u8 {
    return try nodeContent(allocator, doc, attr.children);
}

fn xmlFree(ptr: ?*anyopaque) void {
    c.xmlFree.?(ptr);
}
