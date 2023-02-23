const std = @import("std");
const c = @import("c.zig");
const xml = @import("xml.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const ns = "https://ianjohnson.dev/zig-gobject/extras";

pub const Error = error{InvalidExtras} || Allocator.Error;

pub const Repository = struct {
    namespace: Namespace,
    arena: ArenaAllocator,

    pub fn parseFile(allocator: Allocator, file: [:0]const u8) Error!Repository {
        const doc = xml.parseFile(file) catch return error.InvalidExtras;
        defer c.xmlFreeDoc(doc);
        return try parseDoc(allocator, doc);
    }

    pub fn deinit(self: *Repository) void {
        self.arena.deinit();
    }

    fn parseDoc(a: Allocator, doc: *c.xmlDoc) !Repository {
        var arena = ArenaAllocator.init(a);
        const allocator = arena.allocator();
        const node: *c.xmlNode = c.xmlDocGetRootElement(doc) orelse return error.InvalidExtras;

        var namespace: ?Namespace = null;

        var maybe_child: ?*c.xmlNode = node.children;
        while (maybe_child) |child| : (maybe_child = child.next) {
            if (xml.nodeIs(child, ns, "namespace")) {
                namespace = try parseNamespace(allocator, doc, child);
            }
        }

        return .{
            .namespace = namespace orelse return error.InvalidExtras,
            .arena = arena,
        };
    }
};

pub const Namespace = struct {
    name: []const u8,
    version: []const u8,
    classes: []const Class,
    interfaces: []const Interface,
    records: []const Record,
    functions: []const Function,
    documentation: ?Documentation,
};

fn parseNamespace(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Namespace {
    var name: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var classes = ArrayList(Class).init(allocator);
    var interfaces = ArrayList(Interface).init(allocator);
    var records = ArrayList(Record).init(allocator);
    var functions = ArrayList(Function).init(allocator);
    var documentation: ?Documentation = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (xml.attrIs(attr, null, "name")) {
            name = try xml.attrContent(allocator, doc, attr);
        } else if (xml.attrIs(attr, null, "version")) {
            version = try xml.attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (xml.nodeIs(child, ns, "class")) {
            try classes.append(try parseClass(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "interface")) {
            try interfaces.append(try parseInterface(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "record")) {
            try records.append(try parseRecord(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "doc")) {
            documentation = try parseDocumentation(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidExtras,
        .version = version orelse return error.InvalidExtras,
        .classes = classes.items,
        .interfaces = interfaces.items,
        .records = records.items,
        .functions = functions.items,
        .documentation = documentation,
    };
}

pub const Class = struct {
    name: []const u8,
    functions: []const Function,
    methods: []const Method,
    documentation: ?Documentation,
};

fn parseClass(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Class {
    var name: ?[]const u8 = null;
    var functions = ArrayList(Function).init(allocator);
    var methods = ArrayList(Method).init(allocator);
    var documentation: ?Documentation = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (xml.attrIs(attr, null, "name")) {
            name = try xml.attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (xml.nodeIs(child, ns, "function")) {
            try functions.append(try parseFunction(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "method")) {
            try methods.append(try parseMethod(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "doc")) {
            documentation = try parseDocumentation(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidExtras,
        .functions = functions.items,
        .methods = methods.items,
        .documentation = documentation,
    };
}

pub const Interface = struct {
    name: []const u8,
    functions: []const Function,
    methods: []const Method,
    documentation: ?Documentation,
};

fn parseInterface(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Interface {
    // Interfaces currently have the same structure as classes
    const class = try parseClass(allocator, doc, node);
    return .{
        .name = class.name,
        .functions = class.functions,
        .methods = class.methods,
        .documentation = class.documentation,
    };
}

pub const Record = struct {
    name: []const u8,
    functions: []const Function,
    methods: []const Method,
    documentation: ?Documentation,
};

fn parseRecord(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Record {
    // Records currently have the same structure as classes
    const class = try parseClass(allocator, doc, node);
    return .{
        .name = class.name,
        .functions = class.functions,
        .methods = class.methods,
        .documentation = class.documentation,
    };
}

pub const Function = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    body: []const u8,
    documentation: ?Documentation,
};

fn parseFunction(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Function {
    var name: ?[]const u8 = null;
    var parameters = ArrayList(Parameter).init(allocator);
    var return_value: ?ReturnValue = null;
    var body: ?[]const u8 = null;
    var documentation: ?Documentation = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (xml.attrIs(attr, null, "name")) {
            name = try xml.attrContent(allocator, doc, attr);
        }
    }

    var maybe_child: ?*c.xmlNode = node.children;
    while (maybe_child) |child| : (maybe_child = child.next) {
        if (xml.nodeIs(child, ns, "parameter")) {
            try parameters.append(try parseParameter(allocator, doc, child));
        } else if (xml.nodeIs(child, ns, "return-value")) {
            return_value = try parseReturnValue(allocator, doc, child);
        } else if (xml.nodeIs(child, ns, "body")) {
            body = try xml.nodeContent(allocator, doc, child.children);
        } else if (xml.nodeIs(child, ns, "doc")) {
            documentation = try parseDocumentation(allocator, doc, child);
        }
    }

    return .{
        .name = name orelse return error.InvalidExtras,
        .parameters = parameters.items,
        .return_value = return_value orelse return error.InvalidExtras,
        .body = body orelse return error.InvalidExtras,
        .documentation = documentation,
    };
}

pub const Method = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    body: []const u8,
    documentation: ?Documentation,
};

fn parseMethod(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Method {
    // Methods currently have the same structure as functions
    const function = try parseFunction(allocator, doc, node);
    return .{
        .name = function.name,
        .parameters = function.parameters,
        .return_value = function.return_value,
        .body = function.body,
        .documentation = function.documentation,
    };
}

pub const Parameter = struct {
    name: []const u8,
    type: []const u8,
    @"comptime": bool,
};

fn parseParameter(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Parameter {
    var name: ?[]const u8 = null;
    var @"type": ?[]const u8 = null;
    var @"comptime": bool = false;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        if (xml.attrIs(attr, null, "name")) {
            name = try xml.attrContent(allocator, doc, attr);
        } else if (xml.attrIs(attr, null, "type")) {
            @"type" = try xml.attrContent(allocator, doc, attr);
        } else if (xml.attrIs(attr, null, "comptime")) {
            @"comptime" = std.mem.eql(u8, try xml.attrContent(allocator, doc, attr), "1");
        }
    }

    return .{
        .name = name orelse return error.InvalidExtras,
        .type = @"type" orelse return error.InvalidExtras,
        .@"comptime" = @"comptime",
    };
}

pub const ReturnValue = struct {
    type: []const u8,
};

fn parseReturnValue(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !ReturnValue {
    var @"type": ?[]const u8 = null;

    var maybe_attr: ?*c.xmlAttr = node.properties;
    while (maybe_attr) |attr| : (maybe_attr = attr.next) {
        @"type" = try xml.attrContent(allocator, doc, attr);
    }

    return .{
        .type = @"type" orelse return error.InvalidExtras,
    };
}

pub const Documentation = struct {
    text: []const u8,
};

fn parseDocumentation(allocator: Allocator, doc: *c.xmlDoc, node: *const c.xmlNode) !Documentation {
    return .{ .text = try xml.nodeContent(allocator, doc, node.children) };
}
