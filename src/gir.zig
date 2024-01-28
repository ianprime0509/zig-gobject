const std = @import("std");
const xml = @import("xml");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const FindError = error{ InvalidGir, RepositoryNotFound } || Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError || error{
    FileSystem,
    InputOutput,
    NotSupported,
    Unseekable,
};

/// Finds and parses all repositories for the given root libraries, transitively
/// including dependencies.
pub fn findRepositories(allocator: Allocator, gir_path: []const std.fs.Dir, roots: []const Include) FindError![]Repository {
    var repos = std.ArrayHashMap(Include, Repository, Include.ArrayContext, true).init(allocator);
    defer repos.deinit();
    errdefer for (repos.values()) |*repo| repo.deinit();

    var needed_repos = std.ArrayList(Include).init(allocator);
    defer needed_repos.deinit();
    try needed_repos.appendSlice(roots);
    while (needed_repos.popOrNull()) |needed_repo| {
        if (!repos.contains(needed_repo)) {
            const repo = try findRepository(allocator, gir_path, needed_repo);
            try repos.put(needed_repo, repo);
            try needed_repos.appendSlice(repo.includes);
        }
    }

    return try allocator.dupe(Repository, repos.values());
}

fn findRepository(allocator: Allocator, gir_path: []const std.fs.Dir, include: Include) !Repository {
    const repo_path = try std.fmt.allocPrintZ(allocator, "{s}-{s}.gir", .{ include.name, include.version });
    defer allocator.free(repo_path);
    for (gir_path) |dir| {
        const file = dir.openFile(repo_path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |other| return other,
        };
        defer file.close();
        var reader = std.io.bufferedReader(file.reader());
        return try Repository.parse(allocator, reader.reader());
    }
    return error.RepositoryNotFound;
}

const ns = struct {
    pub const core = "http://www.gtk.org/introspection/core/1.0";
    pub const c = "http://www.gtk.org/introspection/c/1.0";
    pub const glib = "http://www.gtk.org/introspection/glib/1.0";
};

pub const Repository = struct {
    includes: []const Include = &.{},
    packages: []const Package = &.{},
    c_includes: []const CInclude = &.{},
    namespace: Namespace,
    arena: std.heap.ArenaAllocator,

    pub fn parse(allocator: Allocator, reader: anytype) (error{InvalidGir} || @TypeOf(reader).Error || Allocator.Error)!Repository {
        var r = xml.reader(allocator, reader, .{
            .DecoderType = xml.encoding.Utf8Decoder,
            .enable_normalization = false,
        });
        defer r.deinit();
        return parseXml(allocator, &r) catch |err| switch (err) {
            error.CannotUndeclareNsPrefix,
            error.DoctypeNotSupported,
            error.DuplicateAttribute,
            error.InvalidCharacterReference,
            error.InvalidNsBinding,
            error.InvalidPiTarget,
            error.InvalidQName,
            error.MismatchedEndTag,
            error.QNameNotAllowed,
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
        var arena = std.heap.ArenaAllocator.init(a);
        const allocator = arena.allocator();

        var includes = std.ArrayList(Include).init(allocator);
        var packages = std.ArrayList(Package).init(allocator);
        var c_includes = std.ArrayList(CInclude).init(allocator);
        var namespace: ?Namespace = null;

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "include")) {
                    try includes.append(try Include.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "package")) {
                    try packages.append(try Package.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.c, "include")) {
                    try c_includes.append(try CInclude.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "namespace")) {
                    namespace = try Namespace.parse(allocator, child, children.children());
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .includes = try includes.toOwnedSlice(),
            .packages = try packages.toOwnedSlice(),
            .c_includes = try c_includes.toOwnedSlice(),
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

    /// A Context for use in a HashMap.
    pub const Context = struct {
        pub fn hash(_: Context, value: Include) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(value.name);
            hasher.update("-");
            hasher.update(value.version);
            return hasher.final();
        }

        pub fn eql(_: Context, a: Include, b: Include) bool {
            return mem.eql(u8, a.name, b.name) and mem.eql(u8, a.version, b.version);
        }
    };

    /// A Context for use in an ArrayHashMap.
    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, value: Include) u32 {
            return @truncate(Context.hash(.{}, value));
        }

        pub fn eql(_: ArrayContext, a: Include, b: Include, _: usize) bool {
            return Context.eql(.{}, a, b);
        }
    };
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

pub const CInclude = struct {
    name: []const u8,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype) !CInclude {
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
        var aliases = std.ArrayList(Alias).init(allocator);
        var classes = std.ArrayList(Class).init(allocator);
        var interfaces = std.ArrayList(Interface).init(allocator);
        var records = std.ArrayList(Record).init(allocator);
        var unions = std.ArrayList(Union).init(allocator);
        var bit_fields = std.ArrayList(BitField).init(allocator);
        var enums = std.ArrayList(Enum).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var callbacks = std.ArrayList(Callback).init(allocator);
        var constants = std.ArrayList(Constant).init(allocator);

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
                    try aliases.append(try Alias.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "class")) {
                    try classes.append(try Class.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "interface")) {
                    try interfaces.append(try Interface.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "record")) {
                    try records.append(try Record.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "union")) {
                    try unions.append(try Union.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "bitfield")) {
                    try bit_fields.append(try BitField.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "enumeration")) {
                    try enums.append(try Enum.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "callback")) {
                    try callbacks.append(try Callback.parse(allocator, child, children.children(), name.?));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(try Constant.parse(allocator, child, children.children(), name.?));
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{
            .name = name.?,
            .version = version orelse return error.InvalidGir,
            .aliases = try aliases.toOwnedSlice(),
            .classes = try classes.toOwnedSlice(),
            .interfaces = try interfaces.toOwnedSlice(),
            .records = try records.toOwnedSlice(),
            .unions = try unions.toOwnedSlice(),
            .bit_fields = try bit_fields.toOwnedSlice(),
            .enums = try enums.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .callbacks = try callbacks.toOwnedSlice(),
            .constants = try constants.toOwnedSlice(),
        };
    }
};

pub const Alias = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    type: Type,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Alias {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var @"type": ?Type = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
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
            .c_type = c_type,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Class = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    parent: ?Name = null,
    implements: []const Implements = &.{},
    layout_elements: []const LayoutElement,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    get_type: []const u8,
    ref_func: ?[]const u8 = null,
    unref_func: ?[]const u8 = null,
    type_struct: ?Name = null,
    final: bool = false,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn isOpaque(self: Class) bool {
        return self.final or self.layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Class {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var parent: ?Name = null;
        var implements = std.ArrayList(Implements).init(allocator);
        var layout_elements = std.ArrayList(LayoutElement).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var constructors = std.ArrayList(Constructor).init(allocator);
        var methods = std.ArrayList(Method).init(allocator);
        var virtual_methods = std.ArrayList(VirtualMethod).init(allocator);
        var signals = std.ArrayList(Signal).init(allocator);
        var constants = std.ArrayList(Constant).init(allocator);
        var get_type: ?[]const u8 = null;
        var ref_func: ?[]const u8 = null;
        var unref_func: ?[]const u8 = null;
        var type_struct: ?Name = null;
        var final = false;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "parent")) {
                parent = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "ref-func")) {
                ref_func = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "unref-func")) {
                unref_func = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "type-struct")) {
                type_struct = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(null, "final")) {
                final = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "implements")) {
                    try implements.append(try Implements.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "field")) {
                    try layout_elements.append(.{ .field = try Field.parse(allocator, child, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "record")) {
                    try layout_elements.append(.{ .record = try AnonymousRecord.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "union")) {
                    try layout_elements.append(.{ .@"union" = try AnonymousUnion.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "virtual-method")) {
                    try virtual_methods.append(try VirtualMethod.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.glib, "signal")) {
                    try signals.append(try Signal.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(try Constant.parse(allocator, child, children.children(), current_ns));
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
            .c_type = c_type,
            .parent = parent,
            .implements = try implements.toOwnedSlice(),
            .layout_elements = try layout_elements.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .constructors = try constructors.toOwnedSlice(),
            .methods = try methods.toOwnedSlice(),
            .virtual_methods = try virtual_methods.toOwnedSlice(),
            .signals = try signals.toOwnedSlice(),
            .constants = try constants.toOwnedSlice(),
            .get_type = get_type orelse return error.InvalidGir,
            .ref_func = ref_func,
            .unref_func = unref_func,
            .type_struct = type_struct,
            .final = final,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Interface = struct {
    name: Name,
    prerequisites: []const Prerequisite = &.{},
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    get_type: []const u8,
    type_struct: ?Name = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Interface {
        var name: ?Name = null;
        var prerequisites = std.ArrayList(Prerequisite).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var constructors = std.ArrayList(Constructor).init(allocator);
        var methods = std.ArrayList(Method).init(allocator);
        var virtual_methods = std.ArrayList(VirtualMethod).init(allocator);
        var signals = std.ArrayList(Signal).init(allocator);
        var constants = std.ArrayList(Constant).init(allocator);
        var get_type: ?[]const u8 = null;
        var type_struct: ?Name = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "type-struct")) {
                type_struct = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "prerequisite")) {
                    try prerequisites.append(try Prerequisite.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(try Method.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "virtual-method")) {
                    try virtual_methods.append(try VirtualMethod.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.glib, "signal")) {
                    try signals.append(try Signal.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constant")) {
                    try constants.append(try Constant.parse(allocator, child, children.children(), current_ns));
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
            .prerequisites = try prerequisites.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .constructors = try constructors.toOwnedSlice(),
            .methods = try methods.toOwnedSlice(),
            .virtual_methods = try virtual_methods.toOwnedSlice(),
            .signals = try signals.toOwnedSlice(),
            .constants = try constants.toOwnedSlice(),
            .get_type = get_type orelse return error.InvalidGir,
            .type_struct = type_struct,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

pub const Record = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    layout_elements: []const LayoutElement,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    get_type: ?[]const u8 = null,
    disguised: bool = false,
    @"opaque": bool = false,
    pointer: bool = false,
    is_gtype_struct_for: ?Name = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn isPointer(self: Record) bool {
        // The check on is_gtype_struct_for is a heuristic to avoid
        // mistranslations for class types (which are not typedefed pointers)
        return self.pointer or (self.disguised and !self.@"opaque" and self.is_gtype_struct_for == null);
    }

    pub fn isOpaque(self: Record) bool {
        return self.@"opaque" or (self.disguised and !self.pointer) or self.layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Record {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var layout_elements = std.ArrayList(LayoutElement).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var constructors = std.ArrayList(Constructor).init(allocator);
        var methods = std.ArrayList(Method).init(allocator);
        var get_type: ?[]const u8 = null;
        var disguised = false;
        var @"opaque" = false;
        var pointer = false;
        var is_gtype_struct_for: ?Name = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(null, "disguised")) {
                disguised = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "opaque")) {
                @"opaque" = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(null, "pointer")) {
                pointer = mem.eql(u8, attr.value, "1");
            } else if (attr.name.is(ns.glib, "is-gtype-struct-for")) {
                is_gtype_struct_for = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "field")) {
                    try layout_elements.append(.{ .field = try Field.parse(allocator, child, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "record")) {
                    try layout_elements.append(.{ .record = try AnonymousRecord.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "union")) {
                    try layout_elements.append(.{ .@"union" = try AnonymousUnion.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(try Method.parse(allocator, child, children.children(), current_ns));
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
            .c_type = c_type,
            .layout_elements = try layout_elements.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .constructors = try constructors.toOwnedSlice(),
            .methods = try methods.toOwnedSlice(),
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
    name: Name,
    c_type: ?[]const u8 = null,
    layout_elements: []const LayoutElement,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    get_type: ?[]const u8 = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn isOpaque(self: Union) bool {
        return self.layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Union {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var layout_elements = std.ArrayList(LayoutElement).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var constructors = std.ArrayList(Constructor).init(allocator);
        var methods = std.ArrayList(Method).init(allocator);
        var get_type: ?[]const u8 = null;
        var symbol_prefix: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.c, "symbol-prefix")) {
                symbol_prefix = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "field")) {
                    try layout_elements.append(.{ .field = try Field.parse(allocator, child, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "record")) {
                    try layout_elements.append(.{ .record = try AnonymousRecord.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "union")) {
                    try layout_elements.append(.{ .@"union" = try AnonymousUnion.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "constructor")) {
                    try constructors.append(try Constructor.parse(allocator, child, children.children(), current_ns));
                } else if (child.name.is(ns.core, "method")) {
                    try methods.append(try Method.parse(allocator, child, children.children(), current_ns));
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
            .c_type = c_type,
            .layout_elements = try layout_elements.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .constructors = try constructors.toOwnedSlice(),
            .methods = try methods.toOwnedSlice(),
            .get_type = get_type,
            .symbol_prefix = symbol_prefix,
            .documentation = documentation,
        };
    }
};

/// A component of the layout of a class, record, or union.
pub const LayoutElement = union(enum) {
    /// A normal field.
    field: Field,
    /// An anonymous struct field.
    record: AnonymousRecord,
    /// An anonymous union field.
    @"union": AnonymousUnion,
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
                bits = std.fmt.parseInt(u16, attr.value, 10) catch return error.InvalidGir;
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

fn ParseError(comptime Children: type) type {
    // WTF
    const ReaderType = @typeInfo(std.meta.fieldInfo(Children, .reader).type).Pointer.child;
    return error{InvalidGir} || ReaderType.Error || Allocator.Error;
}

pub const AnonymousRecord = struct {
    layout_elements: []const LayoutElement,

    // Explicit error type needed due to https://github.com/ziglang/zig/issues/2971
    fn parse(allocator: Allocator, children: anytype, current_ns: []const u8) ParseError(@TypeOf(children))!AnonymousRecord {
        var layout_elements = std.ArrayList(LayoutElement).init(allocator);

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "field")) {
                    try layout_elements.append(.{ .field = try Field.parse(allocator, child, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "record")) {
                    try layout_elements.append(.{ .record = try AnonymousRecord.parse(allocator, children.children(), current_ns) });
                } else if (child.name.is(ns.core, "union")) {
                    try layout_elements.append(.{ .@"union" = try AnonymousUnion.parse(allocator, children.children(), current_ns) });
                } else {
                    try children.children().skip();
                },
                else => {},
            }
        }

        return .{ .layout_elements = try layout_elements.toOwnedSlice() };
    }
};

pub const AnonymousUnion = struct {
    layout_elements: []const LayoutElement,

    // Explicit error type needed due to https://github.com/ziglang/zig/issues/2971
    fn parse(allocator: Allocator, children: anytype, current_ns: []const u8) ParseError(@TypeOf(children))!AnonymousUnion {
        // AnonymousUnion has the same structure as AnonymousRecord
        const record = try AnonymousRecord.parse(allocator, children, current_ns);
        return .{ .layout_elements = record.layout_elements };
    }
};

pub const BitField = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    members: []const Member,
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !BitField {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var members = std.ArrayList(Member).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "member")) {
                    try members.append(try Member.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
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
            .c_type = c_type,
            .members = try members.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Enum = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    members: []const Member = &.{},
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Enum {
        var name: ?Name = null;
        var c_type: ?[]const u8 = null;
        var members = std.ArrayList(Member).init(allocator);
        var functions = std.ArrayList(Function).init(allocator);
        var get_type: ?[]const u8 = null;
        var documentation: ?Documentation = null;

        for (start.attributes) |attr| {
            if (attr.name.is(null, "name")) {
                name = try Name.parse(allocator, attr.value, current_ns);
            } else if (attr.name.is(ns.c, "type")) {
                c_type = try allocator.dupe(u8, attr.value);
            } else if (attr.name.is(ns.glib, "get-type")) {
                get_type = try allocator.dupe(u8, attr.value);
            }
        }

        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "member")) {
                    try members.append(try Member.parse(allocator, child, children.children()));
                } else if (child.name.is(ns.core, "function")) {
                    try functions.append(try Function.parse(allocator, child, children.children(), current_ns));
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
            .c_type = c_type,
            .members = try members.toOwnedSlice(),
            .functions = try functions.toOwnedSlice(),
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
                value = std.fmt.parseInt(i65, attr.value, 10) catch return error.InvalidGir;
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

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Function {
        var name: ?[]const u8 = null;
        var c_identifier: ?[]const u8 = null;
        var moved_to: ?[]const u8 = null;
        var parameters = std.ArrayList(Parameter).init(allocator);
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
            .parameters = try parameters.toOwnedSlice(),
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
        var parameters = std.ArrayList(Parameter).init(allocator);
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
            .parameters = try parameters.toOwnedSlice(),
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
        var parameters = std.ArrayList(Parameter).init(allocator);
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
            .parameters = try parameters.toOwnedSlice(),
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
                fixed_size = std.fmt.parseInt(u32, attr.value, 10) catch return error.InvalidGir;
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
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, start: xml.Event.ElementStart, children: anytype, current_ns: []const u8) !Callback {
        var name: ?[]const u8 = null;
        var parameters = std.ArrayList(Parameter).init(allocator);
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
            .parameters = try parameters.toOwnedSlice(),
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

    fn parseMany(allocator: Allocator, parameters: *std.ArrayList(Parameter), children: anytype, current_ns: []const u8) !void {
        while (try children.next()) |event| {
            switch (event) {
                .element_start => |child| if (child.name.is(ns.core, "parameter") or child.name.is(ns.core, "instance-parameter")) {
                    try parameters.append(try parse(allocator, child, children.children(), current_ns, child.name.is(ns.core, "instance-parameter")));
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
                closure = std.fmt.parseInt(usize, attr.value, 10) catch return error.InvalidGir;
            } else if (attr.name.is(null, "destroy")) {
                destroy = std.fmt.parseInt(usize, attr.value, 10) catch return error.InvalidGir;
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
        var text = std.ArrayList(u8).init(allocator);
        while (try children.next()) |event| {
            switch (event) {
                .element_content => |e| try text.appendSlice(e.content),
                else => {},
            }
        }
        return .{ .text = try text.toOwnedSlice() };
    }
};

// All the known built-in type names in GIR, which will be associated to the
// null namespace rather than the current namespace being translated. See also
// the map of builtin translations in translate.zig. This map contains fewer
// entries because it is only a set of GIR type names, not C type names.
const builtin_names = std.ComptimeStringMap(void, .{
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
