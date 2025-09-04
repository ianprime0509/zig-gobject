const std = @import("std");
const xml = @import("xml");
const mem = std.mem;
const Allocator = mem.Allocator;
const Diagnostics = @import("main.zig").Diagnostics;

/// Finds and parses all repositories for the given root libraries, transitively
/// including dependencies.
pub fn findRepositories(
    allocator: Allocator,
    gir_dir_paths: []const []const u8,
    gir_fixes_dir_paths: []const []const u8,
    roots: []const Include,
    diag: *Diagnostics,
) Allocator.Error![]Repository {
    var repos = std.ArrayHashMap(Include, Repository, Include.ArrayContext, true).init(allocator);
    defer repos.deinit();
    errdefer for (repos.values()) |*repo| repo.deinit();

    var needed_repos: std.ArrayList(Include) = .empty;
    defer needed_repos.deinit(allocator);
    try needed_repos.appendSlice(allocator, roots);
    while (needed_repos.pop()) |needed_repo| {
        if (!repos.contains(needed_repo)) {
            const repo = findRepository(
                allocator,
                gir_dir_paths,
                gir_fixes_dir_paths,
                needed_repo,
                diag,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.FindFailed => continue,
            };
            try repos.put(needed_repo, repo);
            try needed_repos.appendSlice(allocator, repo.includes);
        }
    }

    return try allocator.dupe(Repository, repos.values());
}

fn findRepository(
    allocator: Allocator,
    gir_dir_paths: []const []const u8,
    gir_fixes_dir_paths: []const []const u8,
    include: Include,
    diag: *Diagnostics,
) !Repository {
    const gir_path = path: {
        const file_name = try std.fmt.allocPrint(allocator, "{s}-{s}.gir", .{ include.name, include.version });
        defer allocator.free(file_name);
        break :path try findFile(allocator, gir_dir_paths, file_name) orelse {
            try diag.add("no GIR file found for {s}-{s}", .{ include.name, include.version });
            return error.FindFailed;
        };
    };

    const gir_fix_path = path: {
        const file_name = try std.fmt.allocPrint(allocator, "{s}-{s}.xslt", .{ include.name, include.version });
        defer allocator.free(file_name);
        break :path try findFile(allocator, gir_fixes_dir_paths, file_name);
    };

    const max_gir_size = 50 * 1024 * 1024;
    const gir_content = content: {
        if (gir_fix_path) |fix_path| {
            const xsltproc_result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "xsltproc", fix_path, gir_path },
                .max_output_bytes = max_gir_size,
                .expand_arg0 = .expand,
            }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |other| {
                    try diag.add("failed to execute xsltproc {s}-{s}: {}", .{ include.name, include.version, other });
                    return error.FindFailed;
                },
            };
            errdefer allocator.free(xsltproc_result.stdout);
            defer allocator.free(xsltproc_result.stderr);
            switch (xsltproc_result.term) {
                .Exited => |status| if (status != 0) {
                    try diag.add(
                        "xsltproc {s}-{s} exited with non-zero status: {}; stderr:\n{s}",
                        .{ include.name, include.version, status, xsltproc_result.stderr },
                    );
                    return error.FindFailed;
                },
                .Signal => |signal| {
                    try diag.add(
                        "xsltproc {s}-{s} exited with signal: {}; stderr:\n{s}",
                        .{ include.name, include.version, signal, xsltproc_result.stderr },
                    );
                    return error.FindFailed;
                },
                .Stopped => |code| {
                    try diag.add(
                        "xsltproc {s}-{s} stopped with code: {}; stderr:\n{s}",
                        .{ include.name, include.version, code, xsltproc_result.stderr },
                    );
                    return error.FindFailed;
                },
                .Unknown => |code| {
                    try diag.add(
                        "xsltproc {s}-{s} terminated with unknown code: {}; stderr:\n{s}",
                        .{ include.name, include.version, code, xsltproc_result.stderr },
                    );
                    return error.FindFailed;
                },
            }
            break :content xsltproc_result.stdout;
        } else {
            break :content std.fs.cwd().readFileAlloc(allocator, gir_path, max_gir_size) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |other| {
                    try diag.add("failed to read GIR file '{s}': {}", .{ gir_path, other });
                    return error.FindFailed;
                },
            };
        }
    };
    defer allocator.free(gir_content);

    return Repository.parse(allocator, gir_path, gir_fix_path, gir_content) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidGir => {
            try diag.add("failed to parse GIR file '{s}'", .{gir_path});
            return error.FindFailed;
        },
    };
}

fn findFile(allocator: Allocator, search_path: []const []const u8, file_name: []const u8) !?[]u8 {
    return for (search_path) |dir| {
        const path = try std.fs.path.join(allocator, &.{ dir, file_name });
        if (std.fs.cwd().statFile(path)) |_| {
            break path;
        } else |_| {
            allocator.free(path);
        }
    } else null;
}

const ns = struct {
    pub const core = "http://www.gtk.org/introspection/core/1.0";
    pub const c = "http://www.gtk.org/introspection/c/1.0";
    pub const glib = "http://www.gtk.org/introspection/glib/1.0";
};

pub const Repository = struct {
    path: []const u8,
    fix_path: ?[]const u8 = null,
    includes: []const Include = &.{},
    packages: []const Package = &.{},
    c_includes: []const CInclude = &.{},
    namespace: Namespace,
    arena: std.heap.ArenaAllocator,

    pub fn parse(
        allocator: Allocator,
        path: []const u8,
        fix_path: ?[]const u8,
        content: []const u8,
    ) (error{InvalidGir} || Allocator.Error)!Repository {
        var static_reader: xml.Reader.Static = .init(allocator, content, .{});
        defer static_reader.deinit();
        return parseXml(allocator, &static_reader.interface, path, fix_path) catch |err| switch (err) {
            error.MalformedXml, error.InvalidGir => return error.InvalidGir,
            error.ReadFailed => unreachable,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    pub fn deinit(repository: *Repository) void {
        repository.arena.deinit();
    }

    fn parseXml(allocator: Allocator, reader: *xml.Reader, path: []const u8, fix_path: ?[]const u8) !Repository {
        try reader.skipProlog();
        if (!reader.elementNameNs().is(ns.core, "repository")) return error.InvalidGir;
        const repository = try parseInternal(allocator, reader, path, fix_path);
        try reader.skipDocument();
        return repository;
    }

    fn parseInternal(a: Allocator, reader: *xml.Reader, path: []const u8, fix_path: ?[]const u8) !Repository {
        var arena = std.heap.ArenaAllocator.init(a);
        const allocator = arena.allocator();

        var includes: std.ArrayList(Include) = .empty;
        var packages: std.ArrayList(Package) = .empty;
        var c_includes: std.ArrayList(CInclude) = .empty;
        var namespace: ?Namespace = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "include")) {
                        try includes.append(allocator, try Include.parse(allocator, reader));
                    } else if (child.is(ns.core, "package")) {
                        try packages.append(allocator, try Package.parse(allocator, reader));
                    } else if (child.is(ns.c, "include")) {
                        try c_includes.append(allocator, try CInclude.parse(allocator, reader));
                    } else if (child.is(ns.core, "namespace")) {
                        namespace = try Namespace.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .path = try allocator.dupe(u8, path),
            .fix_path = if (fix_path) |p| try allocator.dupe(u8, p) else null,
            .includes = try includes.toOwnedSlice(allocator),
            .packages = try packages.toOwnedSlice(allocator),
            .c_includes = try c_includes.toOwnedSlice(allocator),
            .namespace = namespace orelse return error.InvalidGir,
            .arena = arena,
        };
    }
};

pub const Include = struct {
    name: []const u8,
    version: []const u8,

    fn parse(allocator: Allocator, reader: *xml.Reader) !Include {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const version = version: {
            const index = reader.attributeIndex("version") orelse return error.InvalidGir;
            break :version try reader.attributeValueAlloc(allocator, index);
        };

        try reader.skipElement();

        return .{
            .name = name,
            .version = version,
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

    fn parse(allocator: Allocator, reader: *xml.Reader) !Package {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };

        try reader.skipElement();

        return .{
            .name = name,
        };
    }
};

pub const CInclude = struct {
    name: []const u8,

    fn parse(allocator: Allocator, reader: *xml.Reader) !CInclude {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };

        try reader.skipElement();

        return .{
            .name = name,
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

    fn parse(allocator: Allocator, reader: *xml.Reader) !Namespace {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const version = version: {
            const index = reader.attributeIndex("version") orelse return error.InvalidGir;
            break :version try reader.attributeValueAlloc(allocator, index);
        };
        var aliases: std.ArrayList(Alias) = .empty;
        var classes: std.ArrayList(Class) = .empty;
        var interfaces: std.ArrayList(Interface) = .empty;
        var records: std.ArrayList(Record) = .empty;
        var unions: std.ArrayList(Union) = .empty;
        var bit_fields: std.ArrayList(BitField) = .empty;
        var enums: std.ArrayList(Enum) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        var callbacks: std.ArrayList(Callback) = .empty;
        var constants: std.ArrayList(Constant) = .empty;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "alias")) {
                        try aliases.append(allocator, try Alias.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "class")) {
                        try classes.append(allocator, try Class.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "interface")) {
                        try interfaces.append(allocator, try Interface.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "record")) {
                        try records.append(allocator, try Record.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "union")) {
                        try unions.append(allocator, try Union.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "bitfield")) {
                        try bit_fields.append(allocator, try BitField.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "enumeration")) {
                        try enums.append(allocator, try Enum.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "callback")) {
                        try callbacks.append(allocator, try Callback.parse(allocator, reader, name));
                    } else if (child.is(ns.core, "constant")) {
                        try constants.append(allocator, try Constant.parse(allocator, reader, name));
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .version = version,
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
    name: Name,
    c_type: ?[]const u8 = null,
    type: Type,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Alias {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var @"type": ?Type = null;
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = try Type.parse(allocator, reader, current_ns);
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
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
    properties: []const Property = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    callbacks: []const Callback = &.{},
    get_type: ?[]const u8 = null,
    ref_func: ?[]const u8 = null,
    unref_func: ?[]const u8 = null,
    type_struct: ?Name = null,
    final: bool = false,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn isOpaque(class: Class) bool {
        return class.final or class.layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Class {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        const parent = parent: {
            const index = reader.attributeIndex("parent") orelse break :parent null;
            break :parent try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        var implements: std.ArrayList(Implements) = .empty;
        var layout_elements: std.ArrayList(LayoutElement) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        var constructors: std.ArrayList(Constructor) = .empty;
        var methods: std.ArrayList(Method) = .empty;
        var virtual_methods: std.ArrayList(VirtualMethod) = .empty;
        var properties: std.ArrayList(Property) = .empty;
        var signals: std.ArrayList(Signal) = .empty;
        var constants: std.ArrayList(Constant) = .empty;
        var callbacks: std.ArrayList(Callback) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        const ref_func = ref_func: {
            const index = reader.attributeIndexNs(ns.glib, "ref-func") orelse break :ref_func null;
            break :ref_func try reader.attributeValueAlloc(allocator, index);
        };
        const unref_func = unref_func: {
            const index = reader.attributeIndexNs(ns.glib, "unref-func") orelse break :unref_func null;
            break :unref_func try reader.attributeValueAlloc(allocator, index);
        };
        const type_struct = type_struct: {
            const index = reader.attributeIndexNs(ns.glib, "type-struct") orelse break :type_struct null;
            break :type_struct try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const final = final: {
            const index = reader.attributeIndex("final") orelse break :final false;
            break :final mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const symbol_prefix = symbol_prefix: {
            const index = reader.attributeIndexNs(ns.c, "symbol-prefix") orelse break :symbol_prefix null;
            break :symbol_prefix try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "implements")) {
                        try implements.append(allocator, try Implements.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "field")) {
                        try layout_elements.append(allocator, .{ .field = try Field.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "record")) {
                        try layout_elements.append(allocator, .{ .record = try AnonymousRecord.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "union")) {
                        try layout_elements.append(allocator, .{ .@"union" = try AnonymousUnion.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constructor")) {
                        try constructors.append(allocator, try Constructor.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "method")) {
                        try methods.append(allocator, try Method.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "virtual-method")) {
                        try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "property")) {
                        try properties.append(allocator, try Property.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.glib, "signal")) {
                        try signals.append(allocator, try Signal.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constant")) {
                        try constants.append(allocator, try Constant.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "callback")) {
                        try callbacks.append(allocator, try Callback.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .parent = parent,
            .implements = try implements.toOwnedSlice(allocator),
            .layout_elements = try layout_elements.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .virtual_methods = try virtual_methods.toOwnedSlice(allocator),
            .properties = try properties.toOwnedSlice(allocator),
            .signals = try signals.toOwnedSlice(allocator),
            .constants = try constants.toOwnedSlice(allocator),
            .callbacks = try callbacks.toOwnedSlice(allocator),
            .get_type = get_type,
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
    c_type: ?[]const u8 = null,
    prerequisites: []const Prerequisite = &.{},
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    virtual_methods: []const VirtualMethod = &.{},
    properties: []const Property = &.{},
    signals: []const Signal = &.{},
    constants: []const Constant = &.{},
    callbacks: []const Callback = &.{},
    get_type: ?[]const u8 = null,
    type_struct: ?Name = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Interface {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var prerequisites: std.ArrayList(Prerequisite) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        var constructors: std.ArrayList(Constructor) = .empty;
        var methods: std.ArrayList(Method) = .empty;
        var virtual_methods: std.ArrayList(VirtualMethod) = .empty;
        var properties: std.ArrayList(Property) = .empty;
        var signals: std.ArrayList(Signal) = .empty;
        var constants: std.ArrayList(Constant) = .empty;
        var callbacks: std.ArrayList(Callback) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        const type_struct = type_struct: {
            const index = reader.attributeIndexNs(ns.glib, "type-struct") orelse break :type_struct null;
            break :type_struct try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const symbol_prefix = symbol_prefix: {
            const index = reader.attributeIndexNs(ns.c, "symbol-prefix") orelse break :symbol_prefix null;
            break :symbol_prefix try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "prerequisite")) {
                        try prerequisites.append(allocator, try Prerequisite.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constructor")) {
                        try constructors.append(allocator, try Constructor.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "method")) {
                        try methods.append(allocator, try Method.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "virtual-method")) {
                        try virtual_methods.append(allocator, try VirtualMethod.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "property")) {
                        try properties.append(allocator, try Property.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.glib, "signal")) {
                        try signals.append(allocator, try Signal.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constant")) {
                        try constants.append(allocator, try Constant.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "callback")) {
                        try callbacks.append(allocator, try Callback.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .prerequisites = try prerequisites.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
            .virtual_methods = try virtual_methods.toOwnedSlice(allocator),
            .properties = try properties.toOwnedSlice(allocator),
            .signals = try signals.toOwnedSlice(allocator),
            .constants = try constants.toOwnedSlice(allocator),
            .callbacks = try callbacks.toOwnedSlice(allocator),
            .get_type = get_type,
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

    pub fn isPointer(record: Record) bool {
        // The check on is_gtype_struct_for is a heuristic to avoid
        // mistranslations for class types (which are not typedefed pointers)
        return record.pointer or (record.disguised and !record.@"opaque" and record.is_gtype_struct_for == null);
    }

    pub fn isOpaque(record: Record) bool {
        return record.@"opaque" or (record.disguised and !record.pointer) or record.layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Record {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var layout_elements: std.ArrayList(LayoutElement) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        var constructors: std.ArrayList(Constructor) = .empty;
        var methods: std.ArrayList(Method) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        const disguised = disguised: {
            const index = reader.attributeIndex("disguised") orelse break :disguised false;
            break :disguised mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const @"opaque" = @"opaque": {
            const index = reader.attributeIndex("opaque") orelse break :@"opaque" false;
            break :@"opaque" mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const pointer = pointer: {
            const index = reader.attributeIndex("pointer") orelse break :pointer false;
            break :pointer mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const is_gtype_struct_for = is_gtype_struct_for: {
            const index = reader.attributeIndexNs(ns.glib, "is-gtype-struct-for") orelse break :is_gtype_struct_for null;
            break :is_gtype_struct_for try Name.parse(allocator, try reader.attributeValueAlloc(allocator, index), current_ns);
        };
        const symbol_prefix = symbol_prefix: {
            const index = reader.attributeIndexNs(ns.c, "symbol-prefix") orelse break :symbol_prefix null;
            break :symbol_prefix try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "field")) {
                        try layout_elements.append(allocator, .{ .field = try Field.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "record")) {
                        try layout_elements.append(allocator, .{ .record = try AnonymousRecord.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "union")) {
                        try layout_elements.append(allocator, .{ .@"union" = try AnonymousUnion.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constructor")) {
                        try constructors.append(allocator, try Constructor.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "method")) {
                        try methods.append(allocator, try Method.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .layout_elements = try layout_elements.toOwnedSlice(allocator),
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
    name: Name,
    c_type: ?[]const u8 = null,
    layout_elements: []const LayoutElement,
    functions: []const Function = &.{},
    constructors: []const Constructor = &.{},
    methods: []const Method = &.{},
    get_type: ?[]const u8 = null,
    symbol_prefix: ?[]const u8 = null,
    documentation: ?Documentation = null,

    pub fn isOpaque(@"union": Union) bool {
        return @"union".layout_elements.len == 0;
    }

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Union {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var layout_elements: std.ArrayList(LayoutElement) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        var constructors: std.ArrayList(Constructor) = .empty;
        var methods: std.ArrayList(Method) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        const symbol_prefix = symbol_prefix: {
            const index = reader.attributeIndexNs(ns.c, "symbol-prefix") orelse break :symbol_prefix null;
            break :symbol_prefix try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "field")) {
                        try layout_elements.append(allocator, .{ .field = try Field.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "record")) {
                        try layout_elements.append(allocator, .{ .record = try AnonymousRecord.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "union")) {
                        try layout_elements.append(allocator, .{ .@"union" = try AnonymousUnion.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "constructor")) {
                        try constructors.append(allocator, try Constructor.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "method")) {
                        try methods.append(allocator, try Method.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .layout_elements = try layout_elements.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .constructors = try constructors.toOwnedSlice(allocator),
            .methods = try methods.toOwnedSlice(allocator),
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
    bits: ?u16 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Field {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        var @"type": ?FieldType = null;
        const bits = bits: {
            const index = reader.attributeIndex("bits") orelse break :bits null;
            break :bits std.fmt.parseInt(u16, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        @"type" = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "callback")) {
                        @"type" = .{ .callback = try Callback.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
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

pub const AnonymousRecord = struct {
    layout_elements: []const LayoutElement,

    // Explicit error type needed due to https://github.com/ziglang/zig/issues/2971
    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) (@TypeOf(reader.*).ReadError || Allocator.Error || error{InvalidGir})!AnonymousRecord {
        var layout_elements: std.ArrayList(LayoutElement) = .empty;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "field")) {
                        try layout_elements.append(allocator, .{ .field = try Field.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "record")) {
                        try layout_elements.append(allocator, .{ .record = try AnonymousRecord.parse(allocator, reader, current_ns) });
                    } else if (child.is(ns.core, "union")) {
                        try layout_elements.append(allocator, .{ .@"union" = try AnonymousUnion.parse(allocator, reader, current_ns) });
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .layout_elements = try layout_elements.toOwnedSlice(allocator),
        };
    }
};

pub const AnonymousUnion = struct {
    layout_elements: []const LayoutElement,

    // Explicit error type needed due to https://github.com/ziglang/zig/issues/2971
    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) (@TypeOf(reader.*).ReadError || Allocator.Error || error{InvalidGir})!AnonymousUnion {
        // AnonymousUnion has the same structure as AnonymousRecord
        const record = try AnonymousRecord.parse(allocator, reader, current_ns);
        return .{
            .layout_elements = record.layout_elements,
        };
    }
};

pub const BitField = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    /// Extension: the number of bits in the integer type backing the bit field.
    bits: ?u16 = null,
    members: []const Member,
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !BitField {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        const bits = bits: {
            const index = reader.attributeIndex("bits") orelse break :bits null;
            break :bits std.fmt.parseInt(u16, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        var members: std.ArrayList(Member) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "member")) {
                        try members.append(allocator, try Member.parse(allocator, reader));
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .bits = bits,
            .members = try members.toOwnedSlice(allocator),
            .functions = try functions.toOwnedSlice(allocator),
            .get_type = get_type,
            .documentation = documentation,
        };
    }
};

pub const Enum = struct {
    name: Name,
    c_type: ?[]const u8 = null,
    /// Extension: the number of bits in the integer type backing the enum.
    bits: ?u16 = null,
    members: []const Member = &.{},
    functions: []const Function = &.{},
    get_type: ?[]const u8 = null,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Enum {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        const bits = bits: {
            const index = reader.attributeIndex("bits") orelse break :bits null;
            break :bits std.fmt.parseInt(u16, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        var members: std.ArrayList(Member) = .empty;
        var functions: std.ArrayList(Function) = .empty;
        const get_type = get_type: {
            const index = reader.attributeIndexNs(ns.glib, "get-type") orelse break :get_type null;
            break :get_type try reader.attributeValueAlloc(allocator, index);
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "member")) {
                        try members.append(allocator, try Member.parse(allocator, reader));
                    } else if (child.is(ns.core, "function")) {
                        try functions.append(allocator, try Function.parse(allocator, reader, current_ns));
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .bits = bits,
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

    fn parse(allocator: Allocator, reader: *xml.Reader) !Member {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const value = value: {
            const index = reader.attributeIndex("value") orelse return error.InvalidGir;
            break :value std.fmt.parseInt(i65, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .value = value,
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

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Function {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const c_identifier = c_identifier: {
            const index = reader.attributeIndexNs(ns.c, "identifier") orelse return error.InvalidGir;
            break :c_identifier try reader.attributeValueAlloc(allocator, index);
        };
        const moved_to = moved_to: {
            const index = reader.attributeIndex("moved-to") orelse break :moved_to null;
            break :moved_to try reader.attributeValueAlloc(allocator, index);
        };
        var parameters: std.ArrayList(Parameter) = .empty;
        var return_value: ?ReturnValue = null;
        const throws = throws: {
            const index = reader.attributeIndex("throws") orelse break :throws false;
            break :throws mem.eql(u8, try reader.attributeValue(index), "1");
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "parameters")) {
                        try Parameter.parseMany(allocator, &parameters, reader, current_ns);
                    } else if (child.is(ns.core, "return-value")) {
                        return_value = try ReturnValue.parse(allocator, reader, current_ns);
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_identifier = c_identifier,
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

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Constructor {
        // Constructors currently have the same structure as functions
        const function = try Function.parse(allocator, reader, current_ns);
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

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Method {
        // Methods currently have the same structure as functions
        const function = try Function.parse(allocator, reader, current_ns);
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

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !VirtualMethod {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        var parameters: std.ArrayList(Parameter) = .empty;
        var return_value: ?ReturnValue = null;
        const throws = throws: {
            const index = reader.attributeIndex("throws") orelse break :throws false;
            break :throws mem.eql(u8, try reader.attributeValue(index), "1");
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "parameters")) {
                        try Parameter.parseMany(allocator, &parameters, reader, current_ns);
                    } else if (child.is(ns.core, "return-value")) {
                        return_value = try ReturnValue.parse(allocator, reader, current_ns);
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .throws = throws,
            .documentation = documentation,
        };
    }
};

pub const Property = struct {
    name: []const u8,
    type: AnyType,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Property {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        @"type" = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .type = @"type" orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Signal = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_value: ReturnValue,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Signal {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        var parameters: std.ArrayList(Parameter) = .empty;
        var return_value: ?ReturnValue = null;
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "parameters")) {
                        try Parameter.parseMany(allocator, &parameters, reader, current_ns);
                    } else if (child.is(ns.core, "return-value")) {
                        return_value = try ReturnValue.parse(allocator, reader, current_ns);
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .parameters = try parameters.toOwnedSlice(allocator),
            .return_value = return_value orelse return error.InvalidGir,
            .documentation = documentation,
        };
    }
};

pub const Constant = struct {
    name: []const u8,
    c_identifier: ?[]const u8 = null,
    value: []const u8,
    type: AnyType,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Constant {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const c_identifier = c_identifier: {
            const index = reader.attributeIndexNs(ns.c, "identifier") orelse break :c_identifier null;
            break :c_identifier try reader.attributeValueAlloc(allocator, index);
        };
        const value = value: {
            const index = reader.attributeIndex("value") orelse return error.InvalidGir;
            break :value try reader.attributeValueAlloc(allocator, index);
        };
        var @"type": ?AnyType = null;
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        @"type" = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_identifier = c_identifier,
            .value = value,
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
    nullable: bool = false,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Type {
        const name = name: {
            const index = reader.attributeIndex("name") orelse break :name null;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        const nullable = nullable: {
            const index = reader.attributeIndex("nullable") orelse break :nullable false;
            break :nullable mem.eql(u8, try reader.attributeValue(index), "1");
        };

        try reader.skipElement();

        return .{
            .name = name,
            .c_type = c_type,
            .nullable = nullable,
        };
    }
};

pub const ArrayType = struct {
    name: ?Name = null,
    c_type: ?[]const u8 = null,
    element: *const AnyType,
    fixed_size: ?u32 = null,
    zero_terminated: bool = false,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !ArrayType {
        const name = name: {
            const index = reader.attributeIndex("name") orelse break :name null;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var element: ?AnyType = null;
        const fixed_size = fixed_size: {
            const index = reader.attributeIndex("fixed-size") orelse break :fixed_size null;
            break :fixed_size std.fmt.parseInt(u32, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        const zero_terminated = zero_terminated: {
            const index = reader.attributeIndex("zero-terminated") orelse break :zero_terminated false;
            break :zero_terminated mem.eql(u8, try reader.attributeValue(index), "1");
        };

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        element = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        element = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
            .element = element: {
                const copy = try allocator.create(AnyType);
                copy.* = element orelse return error.InvalidGir;
                break :element copy;
            },
            .fixed_size = fixed_size,
            .zero_terminated = zero_terminated,
        };
    }
};

pub const Callback = struct {
    name: []const u8,
    c_type: ?[]const u8 = null,
    parameters: []const Parameter,
    return_value: ReturnValue,
    throws: bool = false,
    documentation: ?Documentation = null,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Callback {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        const c_type = c_type: {
            const index = reader.attributeIndexNs(ns.c, "type") orelse break :c_type null;
            break :c_type try reader.attributeValueAlloc(allocator, index);
        };
        var parameters: std.ArrayList(Parameter) = .empty;
        var return_value: ?ReturnValue = null;
        const throws = throws: {
            const index = reader.attributeIndex("throws") orelse break :throws false;
            break :throws mem.eql(u8, try reader.attributeValue(index), "1");
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "parameters")) {
                        try Parameter.parseMany(allocator, &parameters, reader, current_ns);
                    } else if (child.is(ns.core, "return-value")) {
                        return_value = try ReturnValue.parse(allocator, reader, current_ns);
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .c_type = c_type,
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
    direction: Direction = .in,
    allow_none: bool = false,
    nullable: bool = false,
    optional: bool = false,
    instance: bool = false,
    closure: ?usize = null,
    destroy: ?usize = null,
    documentation: ?Documentation = null,

    pub const Direction = enum {
        in,
        out,
        inout,
    };

    pub fn isOut(parameter: Parameter) bool {
        return switch (parameter.direction) {
            .in => false,
            .out, .inout => true,
        };
    }

    pub fn isNullable(parameter: Parameter) bool {
        return parameter.allow_none or parameter.nullable or parameter.optional;
    }

    fn parseMany(allocator: Allocator, parameters: *std.ArrayList(Parameter), reader: *xml.Reader, current_ns: []const u8) !void {
        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "parameter") or child.is(ns.core, "instance-parameter")) {
                        try parameters.append(allocator, try parse(allocator, reader, current_ns, child.is(ns.core, "instance-parameter")));
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }
    }

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8, instance: bool) !Parameter {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try reader.attributeValueAlloc(allocator, index);
        };
        var @"type": ?ParameterType = null;
        const direction: Direction = direction: {
            const index = reader.attributeIndex("direction") orelse break :direction .in;
            break :direction std.meta.stringToEnum(Direction, try reader.attributeValue(index)) orelse return error.InvalidGir;
        };
        const allow_none = allow_none: {
            const index = reader.attributeIndex("allow-none") orelse break :allow_none false;
            break :allow_none mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const nullable = nullable: {
            const index = reader.attributeIndex("nullable") orelse break :nullable false;
            break :nullable mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const optional = optional: {
            const index = reader.attributeIndex("optional") orelse break :optional false;
            break :optional mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const closure = closure: {
            const index = reader.attributeIndex("closure") orelse break :closure null;
            break :closure std.fmt.parseInt(usize, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        const destroy = destroy: {
            const index = reader.attributeIndex("destroy") orelse break :destroy null;
            break :destroy std.fmt.parseInt(usize, try reader.attributeValue(index), 10) catch return error.InvalidGir;
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        @"type" = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "varargs")) {
                        @"type" = .varargs;
                        try reader.skipElement();
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
                else => {},
            }
        }

        return .{
            .name = name,
            .type = @"type" orelse return error.InvalidGir,
            .direction = direction,
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

    pub fn isNullable(return_value: ReturnValue) bool {
        return return_value.allow_none or return_value.nullable;
    }

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !ReturnValue {
        var @"type": ?AnyType = null;
        const allow_none = allow_none: {
            const index = reader.attributeIndex("allow-none") orelse break :allow_none false;
            break :allow_none mem.eql(u8, try reader.attributeValue(index), "1");
        };
        const nullable = nullable: {
            const index = reader.attributeIndex("nullable") orelse break :nullable false;
            break :nullable mem.eql(u8, try reader.attributeValue(index), "1");
        };
        var documentation: ?Documentation = null;

        while (true) {
            switch (try reader.read()) {
                .element_start => {
                    const child = reader.elementNameNs();
                    if (child.is(ns.core, "type")) {
                        @"type" = .{ .simple = try Type.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "array")) {
                        @"type" = .{ .array = try ArrayType.parse(allocator, reader, current_ns) };
                    } else if (child.is(ns.core, "doc")) {
                        documentation = try Documentation.parse(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                },
                .element_end => break,
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

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Implements {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };

        try reader.skipElement();

        return .{
            .name = name,
        };
    }
};

pub const Prerequisite = struct {
    name: Name,

    fn parse(allocator: Allocator, reader: *xml.Reader, current_ns: []const u8) !Prerequisite {
        const name = name: {
            const index = reader.attributeIndex("name") orelse return error.InvalidGir;
            break :name try Name.parse(allocator, try reader.attributeValue(index), current_ns);
        };

        try reader.skipElement();

        return .{
            .name = name,
        };
    }
};

pub const Documentation = struct {
    text: []const u8,

    fn parse(allocator: Allocator, reader: *xml.Reader) !Documentation {
        return .{
            .text = try reader.readElementTextAlloc(allocator),
        };
    }
};

// All the known built-in type names in GIR, which will be associated to the
// null namespace rather than the current namespace being translated. See also
// the map of builtin translations in translate.zig. This map contains fewer
// entries because it is only a set of GIR type names, not C type names.
const builtin_names: std.StaticStringMap(void) = .initComptime(.{
    .{"gboolean"},
    .{"gchar"},
    .{"guchar"},
    .{"gint8"},
    .{"guint8"},
    .{"gint16"},
    .{"guint16"},
    .{"gint32"},
    .{"guint32"},
    .{"gint64"},
    .{"guint64"},
    .{"gshort"},
    .{"gushort"},
    .{"gint"},
    .{"guint"},
    .{"glong"},
    .{"gulong"},
    .{"gsize"},
    .{"gssize"},
    .{"gintptr"},
    .{"guintptr"},
    .{"gunichar2"},
    .{"gunichar"},
    .{"gfloat"},
    .{"gdouble"},
    .{"va_list"},
    .{"time_t"},
    .{"pid_t"},
    .{"uid_t"},
    .{"none"},
    .{"gpointer"},
    .{"gconstpointer"},
    .{"utf8"},
    .{"filename"},
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
