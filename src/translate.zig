const std = @import("std");
const zigWriter = @import("zig_writer.zig").zigWriter;
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArenaAllocator = heap.ArenaAllocator;
const AutoHashMap = std.AutoHashMap;
const ComptimeStringMap = std.ComptimeStringMap;
const HashMap = std.HashMap;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;

const gir = @import("gir.zig");

pub const Repositories = struct {
    repositories: []const gir.Repository,
    arena: ArenaAllocator,

    pub fn deinit(self: Repositories) void {
        self.arena.deinit();
    }
};

pub const FindError = error{InvalidGir} || Allocator.Error || fs.File.OpenError || error{
    FileSystem,
    InputOutput,
    NotSupported,
};

// Finds and parses all repositories for the given root libraries, transitively
// including dependencies.
pub fn findRepositories(allocator: Allocator, in_dir: fs.Dir, roots: []const []const u8) FindError!Repositories {
    var arena = ArenaAllocator.init(allocator);
    const a = arena.allocator();

    var repos = StringHashMap(gir.Repository).init(a);
    defer repos.deinit();
    var needed_repos = ArrayList([]const u8).init(a);
    try needed_repos.appendSlice(roots);
    while (needed_repos.popOrNull()) |needed_repo| {
        if (!repos.contains(needed_repo)) {
            const repo = try findRepository(a, in_dir, needed_repo);
            try repos.put(needed_repo, repo);
            for (repo.includes) |include| {
                try needed_repos.append(try fmt.allocPrint(a, "{s}-{s}", .{ include.name, include.version }));
            }
        }
    }

    var repos_list = ArrayList(gir.Repository).init(a);
    var repos_iter = repos.valueIterator();
    while (repos_iter.next()) |repo| {
        try repos_list.append(repo.*);
    }

    return .{ .repositories = repos_list.items, .arena = arena };
}

fn findRepository(allocator: Allocator, input_dir: fs.Dir, name: []const u8) !gir.Repository {
    const repo_path = try fmt.allocPrint(allocator, "{s}.gir", .{name});
    defer allocator.free(repo_path);
    const path = try realpathAllocZ(allocator, input_dir, repo_path);
    defer allocator.free(path);
    return try gir.Repository.parseFile(allocator, path);
}

pub const TranslateError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || fs.Dir.CopyFileError || error{
    FileSystem,
    NotSupported,
};

const RepositoryMap = HashMap(gir.Include, gir.Repository, IncludeContext, std.hash_map.default_max_load_percentage);
const IncludeContext = struct {
    pub fn hash(_: IncludeContext, value: gir.Include) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHashStrat(&hasher, value, .Deep);
        return hasher.final();
    }

    pub fn eql(_: IncludeContext, a: gir.Include, b: gir.Include) bool {
        return mem.eql(u8, a.name, b.name) and mem.eql(u8, a.version, b.version);
    }
};

const TranslationContext = struct {
    namespaces: StringHashMapUnmanaged(Namespace),
    arena: ArenaAllocator,

    fn init(allocator: Allocator) TranslationContext {
        var arena = ArenaAllocator.init(allocator);
        return .{
            .namespaces = StringHashMapUnmanaged(Namespace){},
            .arena = arena,
        };
    }

    fn deinit(self: TranslationContext) void {
        self.arena.deinit();
    }

    fn addRepositoryAndDependencies(self: *TranslationContext, repository: gir.Repository, repository_map: RepositoryMap) !void {
        const allocator = self.arena.allocator();
        var seen = HashMap(gir.Include, void, IncludeContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen.deinit();
        var needed_deps = ArrayList(gir.Include).init(allocator);
        defer needed_deps.deinit();
        try needed_deps.append(.{ .name = repository.namespace.name, .version = repository.namespace.version });
        while (needed_deps.popOrNull()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                try seen.put(needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try self.addRepository(dep_repo);
                    try needed_deps.appendSlice(dep_repo.includes);
                }
            }
        }
    }

    fn addRepository(self: *TranslationContext, repository: gir.Repository) !void {
        const allocator = self.arena.allocator();
        var pointer_types = StringHashMapUnmanaged(void){};
        for (repository.namespace.classes) |class| {
            try pointer_types.put(allocator, class.name, {});
        }
        for (repository.namespace.interfaces) |interface| {
            try pointer_types.put(allocator, interface.name, {});
        }
        for (repository.namespace.records) |record| {
            try pointer_types.put(allocator, record.name, {});
        }
        try self.namespaces.put(allocator, repository.namespace.name, .{ .pointer_types = pointer_types });
    }

    fn isPointerType(self: TranslationContext, name: gir.Name) bool {
        if (name.ns) |ns| {
            const namespace = self.namespaces.get(ns) orelse return false;
            return namespace.pointer_types.get(name.local) != null;
        }
        return false;
    }

    const Namespace = struct {
        pointer_types: StringHashMapUnmanaged(void),
    };
};

pub fn translate(repositories: *Repositories, extras_dir: fs.Dir, out_dir: fs.Dir) TranslateError!void {
    const allocator = repositories.arena.allocator();

    var repository_map = RepositoryMap.init(allocator);
    defer repository_map.deinit();
    for (repositories.repositories) |repo| {
        try repository_map.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    for (repositories.repositories) |repo| {
        const source_name = try fmt.allocPrint(allocator, "{s}-{s}", .{ repo.namespace.name, repo.namespace.version });
        defer allocator.free(source_name);
        const extras_file = try copyExtrasFile(allocator, repo.namespace.name, repo.namespace.version, extras_dir, out_dir);
        defer if (extras_file) |path| allocator.free(path);
        var ctx = TranslationContext.init(allocator);
        defer ctx.deinit();
        try ctx.addRepositoryAndDependencies(repo, repository_map);
        try translateRepository(allocator, repo, extras_file, repository_map, ctx, out_dir);
    }
}

fn copyExtrasFile(allocator: Allocator, name: []const u8, version: []const u8, extras_dir: fs.Dir, out_dir: fs.Dir) !?[]u8 {
    const extras_name = try extrasFileNameAlloc(allocator, name, version);
    defer allocator.free(extras_name);
    extras_dir.copyFile(extras_name, out_dir, extras_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    return try allocator.dupe(u8, extras_name);
}

fn extrasFileNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    const file_name = try fmt.allocPrint(allocator, "{s}-{s}.extras.zig", .{ name, version });
    _ = ascii.lowerString(file_name, file_name);
    return file_name;
}

fn realpathAllocZ(allocator: Allocator, dir: fs.Dir, name: []const u8) ![:0]u8 {
    const path = try dir.realpathAlloc(allocator, name);
    defer allocator.free(path);
    return try allocator.dupeZ(u8, path);
}

fn translateRepository(allocator: Allocator, repo: gir.Repository, maybe_extras_path: ?[]const u8, repository_map: RepositoryMap, ctx: TranslationContext, out_dir: fs.Dir) !void {
    const ns = repo.namespace;
    const file_name = try fileNameAlloc(allocator, ns.name, ns.version);
    defer allocator.free(file_name);
    const file = try out_dir.createFile(file_name, .{});
    defer file.close();
    var bw = io.bufferedWriter(file.writer());
    var out = zigWriter(bw.writer());

    if (maybe_extras_path) |path| {
        try out.print("const extras = @import($S);\n", .{path});
    } else {
        try out.print("const extras = struct {};\n", .{});
    }

    try translateIncludes(allocator, ns, repository_map, &out);
    try translateNamespace(allocator, ns, ctx, &out);

    try bw.flush();
    try file.sync();
}

fn translateIncludes(allocator: Allocator, ns: gir.Namespace, repository_map: RepositoryMap, out: anytype) !void {
    // Having the current namespace in scope using the same name makes type
    // translation logic simpler (no need to know what namespace we're in)
    const ns_lower = try ascii.allocLowerString(allocator, ns.name);
    defer allocator.free(ns_lower);
    try out.print("const $I = @This();\n\n", .{ns_lower});

    // std is needed for std.builtin.VaList
    try out.print("const std = @import(\"std\");\n", .{});

    var seen = HashMap(gir.Include, void, IncludeContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer seen.deinit();
    var needed_deps = ArrayList(gir.Include).init(allocator);
    defer needed_deps.deinit();
    if (repository_map.get(.{ .name = ns.name, .version = ns.version })) |dep_repo| {
        try needed_deps.appendSlice(dep_repo.includes);
    }
    while (needed_deps.popOrNull()) |needed_dep| {
        if (!seen.contains(needed_dep)) {
            const module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
            defer allocator.free(module_name);
            const alias = try ascii.allocLowerString(allocator, needed_dep.name);
            defer allocator.free(alias);
            try out.print("const $I = @import($S);\n", .{ alias, module_name });

            try seen.put(needed_dep, {});
            if (repository_map.get(needed_dep)) |dep_repo| {
                try needed_deps.appendSlice(dep_repo.includes);
            }
        }
    }
}

fn fileNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    const file_name = try fmt.allocPrint(allocator, "{s}-{s}.zig", .{ name, version });
    _ = ascii.lowerString(file_name, file_name);
    return file_name;
}

fn moduleNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    const module_name = try fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    _ = ascii.lowerString(module_name, module_name);
    return module_name;
}

fn translateNamespace(allocator: Allocator, ns: gir.Namespace, ctx: TranslationContext, out: anytype) !void {
    for (ns.aliases) |alias| {
        try translateAlias(allocator, alias, ctx, out);
    }
    for (ns.classes) |class| {
        try translateClass(allocator, class, ctx, out);
    }
    for (ns.interfaces) |interface| {
        try translateInterface(allocator, interface, ctx, out);
    }
    for (ns.records) |record| {
        try translateRecord(allocator, record, ctx, out);
    }
    for (ns.unions) |@"union"| {
        try translateUnion(allocator, @"union", ctx, out);
    }
    for (ns.enums) |@"enum"| {
        try translateEnum(allocator, @"enum", ctx, out);
    }
    for (ns.bit_fields) |bit_field| {
        try translateBitField(allocator, bit_field, ctx, out);
    }
    for (ns.functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    for (ns.callbacks) |callback| {
        try translateCallback(allocator, callback, true, ctx, out);
    }
    for (ns.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("pub usingnamespace if (@hasDecl(extras, \"namespace\")) extras.namespace else struct {};\n", .{});
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(alias.documentation, out);
    try out.print("pub const $I = ", .{alias.name});
    try translateType(allocator, alias.type, .{}, ctx, out);
    try out.print(";\n\n", .{});
}

fn translateClass(allocator: Allocator, class: gir.Class, ctx: TranslationContext, out: anytype) !void {
    // class type
    try translateDocumentation(class.documentation, out);
    try out.print("pub const $I = ", .{class.name});
    if (class.final) {
        try out.print("opaque ${\n", .{});
    } else {
        try out.print("extern struct ${\n", .{});
    }

    const parent = class.parent orelse gir.Name{ .ns = "GObject", .local = "TypeInstance" };
    try out.print("pub const Parent = ", .{});
    try translateName(allocator, parent, out);
    try out.print(";\n", .{});

    try out.print("pub const Implements = [_]type{", .{});
    for (class.implements, 0..) |implements, i| {
        try translateName(allocator, implements.name, out);
        if (i < class.implements.len - 1) {
            try out.print(", ", .{});
        }
    }
    try out.print("};\n", .{});

    if (class.type_struct) |type_struct| {
        try out.print("pub const Class = $I;\n", .{type_struct});
    }
    try out.print("const Self = $I;\n\n", .{class.name});

    for (class.fields) |field| {
        try translateField(allocator, field, ctx, out);
    }
    if (class.fields.len > 0) {
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct${\n", .{});
    const get_type_function = class.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, ctx, out);
    }
    for (class.functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    for (class.constructors) |constructor| {
        try translateConstructor(allocator, constructor, ctx, out);
    }
    for (class.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{class.name});
    try out.print("pub const Methods = $LMethods;\n", .{class.name});
    if (class.type_struct != null) {
        try out.print("pub const OwnVirtualMethods = $LOwnVirtualMethods;\n", .{class.name});
        try out.print("pub const VirtualMethods = $LVirtualMethods;\n", .{class.name});
        try out.print("pub const ExtraVirtualMethods = $LExtraVirtualMethods;\n", .{class.name});
    }
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ class.name, class.name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{class.name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime Self: type) type ${\n", .{class.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct${\n", .{});
    for (class.methods) |method| {
        try translateMethod(allocator, method, ctx, out);
    }
    for (class.signals) |signal| {
        try translateSignal(allocator, signal, ctx, out);
    }
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LMethods(comptime Self: type) type ${\n", .{class.name});
    try out.print("return struct${\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(Self);\n", .{class.name});
    try out.print("pub usingnamespace $I.Parent.Methods(Self);\n", .{class.name});
    for (class.implements) |implements| {
        try out.print("pub usingnamespace ", .{});
        try translateName(allocator, implements.name, out);
        try out.print(".Methods(Self);\n", .{});
    }
    try out.print("pub usingnamespace $LExtraMethods(Self);\n", .{class.name});
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime Self: type) type ${\n", .{class.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(Self) else struct {};\n", .{ class.name, class.name });
    try out.print("$}\n\n", .{});

    // virtual methods mixins
    if (class.type_struct) |type_struct| {
        try out.print("fn $LOwnVirtualMethods(comptime Class: type, comptime Instance: type) type ${\n", .{class.name});
        try out.print(
            \\const _i_dont_care_if_Class_is_unused = Class;
            \\_ = _i_dont_care_if_Class_is_unused;
            \\const _i_dont_care_if_Instance_is_unused = Instance;
            \\_ = _i_dont_care_if_Instance_is_unused;
            \\
        , .{});
        try out.print("return struct${\n", .{});
        for (class.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, "Class", type_struct, class.name, ctx, out);
        }
        try out.print("$};\n", .{});
        try out.print("$}\n\n", .{});

        try out.print("fn $LVirtualMethods(comptime Class: type, comptime Instance: type) type ${\n", .{class.name});
        try out.print("return struct${\n", .{});
        try out.print("pub usingnamespace $LOwnVirtualMethods(Class, Instance);\n", .{class.name});
        if (class.parent != null) {
            try out.print("pub usingnamespace if (@hasDecl($I.Parent, \"VirtualMethods\")) $I.Parent.VirtualMethods(Class, Instance) else struct {};\n", .{ class.name, class.name });
        }
        try out.print("pub usingnamespace $LExtraVirtualMethods(Class, Instance);\n", .{class.name});
        try out.print("$};\n", .{});
        try out.print("$}\n\n", .{});

        try out.print("fn $LExtraVirtualMethods(comptime Class: type, comptime Instance: type) type ${\n", .{class.name});
        try out.print("return if (@hasDecl(extras, \"$LVirtualMethods\")) extras.$LVirtualMethods(Class, Instance) else struct {};\n", .{ class.name, class.name });
        try out.print("$}\n\n", .{});
    }
}

fn translateInterface(allocator: Allocator, interface: gir.Interface, ctx: TranslationContext, out: anytype) !void {
    // interface type
    try translateDocumentation(interface.documentation, out);
    try out.print("pub const $I = opaque ${\n", .{interface.name});

    try out.print("pub const Prerequisites = [_]type{", .{});
    // This doesn't seem to be correct (since it seems to be possible to create
    // an interface with actually no prerequisites), but it seems to be assumed
    // by GIR documentation generation tools
    if (interface.prerequisites.len == 0) {
        try out.print("gobject.Object", .{});
    }
    for (interface.prerequisites, 0..) |prerequisite, i| {
        try translateName(allocator, prerequisite.name, out);
        if (i < interface.prerequisites.len - 1) {
            try out.print(", ", .{});
        }
    }
    try out.print("};\n", .{});

    if (interface.type_struct) |type_struct| {
        try out.print("pub const Iface = $I;\n", .{type_struct});
    }
    try out.print("const Self = $I;\n\n", .{interface.name});

    try out.print("pub const Own = struct${\n", .{});
    const get_type_function = interface.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, ctx, out);
    }
    for (interface.functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    for (interface.constructors) |constructor| {
        try translateConstructor(allocator, constructor, ctx, out);
    }
    for (interface.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{interface.name});
    try out.print("pub const Methods = $LMethods;\n", .{interface.name});
    if (interface.type_struct != null) {
        try out.print("pub const OwnVirtualMethods = $LOwnVirtualMethods;\n", .{interface.name});
        try out.print("pub const VirtualMethods = $LVirtualMethods;\n", .{interface.name});
        try out.print("pub const ExtraVirtualMethods = $LExtraVirtualMethods;\n", .{interface.name});
    }
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ interface.name, interface.name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{interface.name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime Self: type) type ${\n", .{interface.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct${\n", .{});
    for (interface.methods) |method| {
        try translateMethod(allocator, method, ctx, out);
    }
    for (interface.signals) |signal| {
        try translateSignal(allocator, signal, ctx, out);
    }
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LMethods(comptime Self: type) type ${\n", .{interface.name});
    try out.print("return struct ${\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(Self);\n", .{interface.name});
    // See the note above on this implicit prerequisite
    if (interface.prerequisites.len == 0) {
        try out.print("pub usingnamespace gobject.Object.Methods(Self);\n", .{});
    }
    for (interface.prerequisites) |prerequisite| {
        try out.print("pub usingnamespace ", .{});
        try translateName(allocator, prerequisite.name, out);
        try out.print(".Methods(Self);\n", .{});
    }
    try out.print("pub usingnamespace $LExtraMethods(Self);\n", .{interface.name});
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime Self: type) type ${\n", .{interface.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(Self) else struct {};\n", .{ interface.name, interface.name });
    try out.print("$}\n\n", .{});

    // virtual methods mixins
    if (interface.type_struct) |type_struct| {
        try out.print("fn $LOwnVirtualMethods(comptime Iface: type, comptime Instance: type) type ${\n", .{interface.name});
        try out.print(
            \\const _i_dont_care_if_Iface_is_unused = Iface;
            \\_ = _i_dont_care_if_Iface_is_unused;
            \\const _i_dont_care_if_Instance_is_unused = Instance;
            \\_ = _i_dont_care_if_Instance_is_unused;
            \\
        , .{});
        try out.print("return struct${\n", .{});
        for (interface.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, "Iface", type_struct, interface.name, ctx, out);
        }
        try out.print("$};\n", .{});
        try out.print("$}\n\n", .{});

        try out.print("fn $LVirtualMethods(comptime Iface: type, comptime Instance: type) type ${\n", .{interface.name});
        try out.print("return struct${\n", .{});
        try out.print("pub usingnamespace $LOwnVirtualMethods(Iface, Instance);\n", .{interface.name});
        try out.print("pub usingnamespace $LExtraVirtualMethods(Iface, Instance);\n", .{interface.name});
        try out.print("$};\n", .{});
        try out.print("$}\n\n", .{});

        try out.print("fn $LExtraVirtualMethods(comptime Iface: type, comptime Instance: type) type ${\n", .{interface.name});
        try out.print("return if (@hasDecl(extras, \"$LVirtualMethods\")) extras.$LVirtualMethods(Iface, Instance) else struct {};\n", .{ interface.name, interface.name });
        try out.print("$}\n\n", .{});
    }
}

fn translateRecord(allocator: Allocator, record: gir.Record, ctx: TranslationContext, out: anytype) !void {
    // record type
    try translateDocumentation(record.documentation, out);
    try out.print("pub const $I = ", .{record.name});
    if (record.isPointer()) {
        try out.print("*", .{});
    }
    if (record.isOpaque()) {
        try out.print("opaque ${\n", .{});
    } else {
        try out.print("extern struct ${\n", .{});
    }

    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print("pub const Instance = $I;\n", .{is_gtype_struct_for});
    }
    try out.print("const Self = $I;\n\n", .{record.name});
    for (record.fields) |field| {
        try translateField(allocator, field, ctx, out);
    }
    if (record.fields.len > 0) {
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct${\n", .{});
    if (record.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, ctx, out);
        }
    }
    for (record.functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    for (record.constructors) |constructor| {
        try translateConstructor(allocator, constructor, ctx, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{record.name});
    try out.print("pub const Methods = $LMethods;\n", .{record.name});
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ record.name, record.name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{record.name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(Self);\n", .{});
    if (record.is_gtype_struct_for != null) {
        try out.print("pub usingnamespace Instance.VirtualMethods(Self, Instance);\n", .{});
    }
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime Self: type) type ${\n", .{record.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct${\n", .{});
    for (record.methods) |method| {
        try translateMethod(allocator, method, ctx, out);
    }
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LMethods(comptime Self: type) type ${\n", .{record.name});
    try out.print("return struct${\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(Self);\n", .{record.name});
    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print(
            \\pub usingnamespace if (@hasDecl($I, "Parent") and @hasDecl($I.Parent, "Class"))
            \\    $I.Parent.Class.Methods(Self)
            \\else if (@hasDecl($I, "Parent"))
            \\    gobject.TypeClass.Methods(Self)
            \\else
            \\    struct{}
            \\;
            \\
        , .{ is_gtype_struct_for, is_gtype_struct_for, is_gtype_struct_for, is_gtype_struct_for });
    }
    try out.print("pub usingnamespace $LExtraMethods(Self);\n", .{record.name});
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime Self: type) type ${\n", .{record.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(Self) else struct {};\n", .{ record.name, record.name });
    try out.print("$}\n\n", .{});
}

fn translateUnion(allocator: Allocator, @"union": gir.Union, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(@"union".documentation, out);
    try out.print("pub const $I = extern union ${\n", .{@"union".name});
    try out.print("const Self = $I;\n\n", .{@"union".name});
    for (@"union".fields) |field| {
        try translateField(allocator, field, ctx, out);
    }
    if (@"union".fields.len > 0) {
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct${\n", .{});
    if (@"union".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, ctx, out);
        }
    }
    for (@"union".functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    for (@"union".constructors) |constructor| {
        try translateConstructor(allocator, constructor, ctx, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{@"union".name});
    try out.print("pub const Methods = $LMethods;\n", .{@"union".name});
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ @"union".name, @"union".name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{@"union".name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime Self: type) type ${\n", .{@"union".name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct${\n", .{});
    for (@"union".methods) |method| {
        try translateMethod(allocator, method, ctx, out);
    }
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LMethods(comptime Self: type) type ${\n", .{@"union".name});
    try out.print("return struct${\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(Self);\n", .{@"union".name});
    try out.print("pub usingnamespace $LExtraMethods(Self);\n", .{@"union".name});
    try out.print("$};\n", .{});
    try out.print("$}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime Self: type) type ${\n", .{@"union".name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(Self) else struct {};\n", .{ @"union".name, @"union".name });
    try out.print("$}\n\n", .{});
}

fn translateField(allocator: Allocator, field: gir.Field, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(field.documentation, out);
    try out.print("$I: ", .{field.name});
    try translateFieldType(allocator, field.type, ctx, out);
    try out.print(",\n", .{});
}

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, ctx: TranslationContext, out: anytype) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, .{ .nullable = true }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{ .nullable = true }, ctx, out),
        .callback => |callback| try translateCallback(allocator, callback, false, ctx, out),
    }
}

fn translateBitField(allocator: Allocator, bit_field: gir.BitField, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(bit_field.documentation, out);
    var paddingNeeded: usize = @bitSizeOf(c_uint);
    try out.print("pub const $I = packed struct(c_uint) ${\n", .{bit_field.name});
    for (bit_field.members) |member| {
        if (member.value > 0) {
            try out.print("$I: bool = false,\n", .{member.name});
            paddingNeeded -= 1;
        }
    }
    if (paddingNeeded > 0) {
        try out.print("_: u$L = 0,\n", .{paddingNeeded});
    }

    try out.print("\nconst Self = $I;\n\n", .{bit_field.name});

    try out.print("pub const Own = struct${\n", .{});
    if (bit_field.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, ctx, out);
        }
    }
    for (bit_field.functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n\n", .{ bit_field.name, bit_field.name });

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});
}

fn translateEnum(allocator: Allocator, @"enum": gir.Enum, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(@"enum".documentation, out);
    try out.print("pub const $I = enum(c_int) ${\n", .{@"enum".name});

    // Zig does not allow enums to have multiple fields with the same value, so
    // we must translate any duplicate values as constants referencing the
    // "base" value
    var seen_values = AutoHashMap(i64, gir.Member).init(allocator);
    defer seen_values.deinit();
    var duplicate_members = ArrayList(gir.Member).init(allocator);
    defer duplicate_members.deinit();
    for (@"enum".members) |member| {
        if (seen_values.get(member.value) == null) {
            try out.print("$I = $L,\n", .{ member.name, member.value });
            try seen_values.put(member.value, member);
        } else {
            try duplicate_members.append(member);
        }
    }

    try out.print("\nconst Self = $I;\n\n", .{@"enum".name});

    for (duplicate_members.items) |member| {
        try out.print("pub const $I = Self.$I;\n", .{ member.name, seen_values.get(member.value).?.name });
    }

    try out.print("pub const Own = struct${\n", .{});
    if (@"enum".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, ctx, out);
        }
    }
    for (@"enum".functions) |function| {
        try translateFunction(allocator, function, ctx, out);
    }
    try out.print("$};\n\n", .{});

    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n\n", .{ @"enum".name, @"enum".name });

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("$};\n\n", .{});
}

fn isFunctionTranslatable(function: gir.Function) bool {
    return function.moved_to == null;
}

fn translateFunction(allocator: Allocator, function: gir.Function, ctx: TranslationContext, out: anytype) !void {
    if (!isFunctionTranslatable(function)) {
        return;
    }

    var fnName = try toCamelCase(allocator, function.name, "_");
    defer allocator.free(fnName);
    // There is a function named `dummy` declared in libxml2-2.0.gir which has
    // the same name and c_identifier. I don't know why it's there, or even if
    // it's a real function that exists in the library. But it's in the GIR, so
    // this translator has to account for it.
    const needs_rename = !std.mem.eql(u8, fnName, function.c_identifier);

    // extern declaration
    if (!needs_rename) {
        try translateDocumentation(function.documentation, out);
        try out.print("pub ", .{});
    }
    try out.print("extern fn $I(", .{function.c_identifier});
    try translateParameters(allocator, function.parameters, .{ .throws = function.throws }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, function.return_value, .{ .nullable = function.throws }, ctx, out);
    try out.print(";\n", .{});

    // function rename
    if (needs_rename) {
        try translateDocumentation(function.documentation, out);
        try out.print("pub const $I = $I;\n\n", .{ fnName, function.c_identifier });
    }
}

fn isConstructorTranslatable(constructor: gir.Constructor) bool {
    return constructor.moved_to == null;
}

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, ctx: TranslationContext, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = constructor.name,
        .c_identifier = constructor.c_identifier,
        .moved_to = constructor.moved_to,
        .parameters = constructor.parameters,
        // This is a somewhat hacky way to ensure the constructor always returns
        // the type it's constructing and not some less specific type (like
        // certain GTK widget constructors which return Widget rather than the
        // actual type being constructed)
        // TODO: consider if the return value is const, or maybe not even a pointer at all
        .return_value = .{ .type = .{ .simple = .{
            .name = .{ .ns = null, .local = "Self" },
            .c_type = "Self*",
        } } },
        .throws = constructor.throws,
        .documentation = constructor.documentation,
    }, ctx, out);
}

fn isMethodTranslatable(method: gir.Method) bool {
    return method.moved_to == null;
}

fn translateMethod(allocator: Allocator, method: gir.Method, ctx: TranslationContext, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = method.name,
        .c_identifier = method.c_identifier,
        .moved_to = method.moved_to,
        .parameters = method.parameters,
        .return_value = method.return_value,
        .throws = method.throws,
        .documentation = method.documentation,
    }, ctx, out);
}

fn translateVirtualMethod(allocator: Allocator, virtual_method: gir.VirtualMethod, container_name: []const u8, container_type: []const u8, instance_type: []const u8, ctx: TranslationContext, out: anytype) !void {
    var upper_method_name = try toCamelCase(allocator, virtual_method.name, "_");
    defer allocator.free(upper_method_name);
    if (upper_method_name.len > 0) {
        upper_method_name[0] = ascii.toUpper(upper_method_name[0]);
    }

    // implementation
    try translateDocumentation(virtual_method.documentation, out);
    try out.print("pub fn implement$L(p_class: *$I, p_implementation: ", .{ upper_method_name, container_name });
    try translateVirtualMethodImplementationType(allocator, virtual_method, "Instance", ctx, out);
    try out.print(") void ${\n", .{});
    try out.print("@ptrCast(*$I, @alignCast(@alignOf(*$I), p_class)).$I = @ptrCast(", .{ container_type, container_type, virtual_method.name });
    try translateVirtualMethodImplementationType(allocator, virtual_method, instance_type, ctx, out);
    try out.print(", p_implementation);\n", .{});
    try out.print("$}\n\n", .{});

    // call
    try out.print("pub fn call$L(p_class: *$I, ", .{ upper_method_name, container_name });
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{ .nullable = virtual_method.throws }, ctx, out);
    try out.print(" ${\n", .{});
    try out.print("return @ptrCast(*$I, @alignCast(@alignOf(*$I), p_class)).$I.?(", .{ container_type, container_type, virtual_method.name });
    try translateParameterNames(allocator, virtual_method.parameters, .{ .throws = virtual_method.throws }, out);
    try out.print(");\n", .{});
    try out.print("$}\n\n", .{});
}

fn translateVirtualMethodImplementationType(allocator: Allocator, virtual_method: gir.VirtualMethod, instance_type: []const u8, ctx: TranslationContext, out: anytype) !void {
    try out.print("*const fn (", .{});
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") callconv(.C) ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{ .nullable = virtual_method.throws }, ctx, out);
}

fn translateSignal(allocator: Allocator, signal: gir.Signal, ctx: TranslationContext, out: anytype) !void {
    var upper_signal_name = try toCamelCase(allocator, signal.name, "-");
    defer allocator.free(upper_signal_name);
    if (upper_signal_name.len > 0) {
        upper_signal_name[0] = ascii.toUpper(upper_signal_name[0]);
    }

    // normal connection
    try translateDocumentation(signal.documentation, out);
    try out.print("pub fn connect$L(p_self: *Self, comptime T: type, p_callback: ", .{upper_signal_name});
    // TODO: verify that T is a pointer type or compatible
    try translateSignalCallbackType(allocator, signal, ctx, out);
    try out.print(", p_data: T, p_options: struct { after: bool = false }) c_ulong ${\n", .{});
    try out.print("return gobject.signalConnectData(p_self, $S, @ptrCast(gobject.Callback, p_callback), p_data, null, .{ .after = p_options.after });\n", .{signal.name});
    try out.print("$}\n\n", .{});
}

fn translateSignalCallbackType(allocator: Allocator, signal: gir.Signal, ctx: TranslationContext, out: anytype) !void {
    try out.print("*const fn (*Self", .{});
    if (signal.parameters.len > 0) {
        try out.print(", ", .{});
    }
    try translateParameters(allocator, signal.parameters, .{ .gobject_context = true }, ctx, out);
    try out.print(", T) callconv(.C) ", .{});
    try translateReturnValue(allocator, signal.return_value, .{ .gobject_context = true }, ctx, out);
}

fn translateConstant(constant: gir.Constant, out: anytype) !void {
    try translateDocumentation(constant.documentation, out);
    if (constant.type == .simple and constant.type.simple.name != null and mem.eql(u8, constant.type.simple.name.?.local, "utf8")) {
        try out.print("pub const $I = $S;\n", .{ constant.name, constant.value });
    } else {
        try out.print("pub const $I = $L;\n", .{ constant.name, constant.value });
    }
}

// See also the set of built-in type names in gir.zig. This map contains more
// entries because it also handles mappings from C types, not just GIR type
// names.
const builtins = ComptimeStringMap([]const u8, .{
    .{ "gboolean", "bool" },
    .{ "char", "u8" },
    .{ "gchar", "u8" },
    .{ "unsigned char", "u8" },
    .{ "guchar", "u8" },
    .{ "int8_t", "i8" },
    .{ "gint8", "i8" },
    .{ "uint8_t", "u8" },
    .{ "guint8", "u8" },
    .{ "int16_t", "i16" },
    .{ "gint16", "i16" },
    .{ "uint16_t", "u16" },
    .{ "guint16", "u16" },
    .{ "int32_t", "i32" },
    .{ "gint32", "i32" },
    .{ "uint32_t", "u32" },
    .{ "guint32", "u32" },
    .{ "int64_t", "i64" },
    .{ "gint64", "i64" },
    .{ "uint64_t", "u64" },
    .{ "guint64", "u64" },
    .{ "short", "c_short" },
    .{ "gshort", "c_short" },
    .{ "unsigned short", "c_ushort" },
    .{ "gushort", "c_ushort" },
    .{ "int", "c_int" },
    .{ "gint", "c_int" },
    .{ "unsigned int", "c_uint" },
    .{ "guint", "c_uint" },
    .{ "long", "c_long" },
    .{ "glong", "c_long" },
    .{ "unsigned long", "c_ulong" },
    .{ "gulong", "c_ulong" },
    .{ "size_t", "usize" },
    .{ "gsize", "usize" },
    .{ "ssize_t", "isize" },
    .{ "gssize", "isize" },
    .{ "gunichar2", "u16" },
    .{ "gunichar", "u32" },
    .{ "float", "f32" },
    .{ "gfloat", "f32" },
    .{ "double", "f64" },
    .{ "gdouble", "f64" },
    .{ "long double", "c_longdouble" },
    .{ "va_list", "std.builtin.VaList" },
    // It might make sense on the surface to include void -> void as a mapping
    // here, but actually we don't want void to be a built-in type translated to
    // void, because a c_type of void may just be a type-erased buffer whose
    // element type is given in the name of the type. The none -> void mapping
    // should cover all legitimate uses of raw void in C.
    .{ "none", "void" },
    // Not all repositories declare a dependency on either GLib or GObject, but they
    // might still reference GType in their bindings for some reason. Since
    // GType is defined as an alias for usize, we can just translate it as such,
    // even though it makes for subpar documentation. The alternative would be
    // to force every repository to depend on GLib, but that is more complex and
    // incorrect.
    .{ "GType", "usize" },
    // We need to be particularly careful about built-in pointer types, since
    // those can mess up the translation logic if they're not processed early on
    .{ "gpointer", "*anyopaque" },
    .{ "gconstpointer", "*const anyopaque" },
    .{ "void*", "*anyopaque" },
    .{ "const void*", "*const anyopaque" },
    .{ "utf8", "[*:0]u8" },
    .{ "filename", "[*:0]u8" },
});

const TranslateTypeOptions = struct {
    /// Whether the type should be translated as nullable.
    nullable: bool = false,
    /// Whether the type is being translated in a GObject-specific context, such
    /// as a signal or property, where types are often specified without any
    /// corresponding C type and in such a case are meant to be assumed to be
    /// pointers.
    gobject_context: bool = false,
};

fn translateAnyType(allocator: Allocator, @"type": gir.AnyType, options: TranslateTypeOptions, ctx: TranslationContext, out: anytype) !void {
    switch (@"type") {
        .simple => |simple| try translateType(allocator, simple, options, ctx, out),
        .array => |array| try translateArrayType(allocator, array, options, ctx, out),
    }
}

fn translateType(allocator: Allocator, @"type": gir.Type, options: TranslateTypeOptions, ctx: TranslationContext, out: anytype) TranslateError!void {
    const name = @"type".name orelse {
        const c_type = @"type".c_type orelse {
            try out.print("@compileError(\"no type information available\")", .{});
            return;
        };
        // Last-ditch attempt to salvage some code generation by translating pointers as opaque
        if (parseCPointerType(c_type)) |pointer| {
            if (options.nullable) {
                try out.print("?", .{});
            }
            if (pointer.@"const") {
                try out.print("*const anyopaque", .{});
            } else {
                try out.print("*anyopaque", .{});
            }
            return;
        }
        try out.print("@compileError(\"not enough type information available\")", .{});
        return;
    };
    var c_type = @"type".c_type orelse {
        // We should check for builtins first; utf8 is a common type to end up with here
        if (builtins.get(name.local)) |builtin| {
            if (options.nullable and (std.mem.startsWith(u8, builtin, "*") or std.mem.startsWith(u8, builtin, "[*"))) {
                try out.print("?", .{});
            }
            try out.print("$L", .{builtin});
            return;
        }

        // At this point, the only thing we can do is assume a plain type. GIR
        // is extremely annoying when it comes to precisely representing types
        // in certain contexts, such as signals and properties (basically
        // anything that doesn't have a direct C equivalent). The context is
        // needed here to correctly guess whether the type should be a pointer
        // or not.
        if (options.gobject_context and ctx.isPointerType(name)) {
            if (options.nullable) {
                try out.print("?", .{});
            }
            try out.print("*", .{});
        }
        try translateName(allocator, name, out);
        return;
    };

    // The c_type is more reliable than name when looking for builtins, since
    // the name often does not include any information about whether the type is
    // a pointer
    if (builtins.get(c_type)) |builtin| {
        if (options.nullable and (std.mem.startsWith(u8, builtin, "*") or std.mem.startsWith(u8, builtin, "[*"))) {
            try out.print("?", .{});
        }
        try out.print("$L", .{builtin});
        return;
    }

    if (parseCPointerType(c_type)) |pointer| {
        if (options.nullable) {
            try out.print("?", .{});
        }
        // Special case: utf8 and filename should be treated as C strings
        if (name.ns == null and (std.mem.eql(u8, name.local, "utf8") or std.mem.eql(u8, name.local, "filename")) and parseCPointerType(pointer.element) == null) {
            try out.print("[*:0]", .{});
        } else {
            try out.print("*", .{});
        }
        if (pointer.@"const") {
            try out.print("const ", .{});
        }
        // Nullability does not apply recursively.
        // TODO: how does GIR expect to represent nullability more than one level deep?
        return translateType(allocator, .{ .name = name, .c_type = pointer.element }, .{ .gobject_context = options.gobject_context }, ctx, out);
    }

    // Unnecessary const qualifier for non-pointer type
    if (std.mem.startsWith(u8, c_type, "const ")) {
        c_type = c_type["const ".len..];
        return translateType(allocator, .{ .name = name, .c_type = c_type }, options, ctx, out);
    }

    // At this point, we've exhausted explicit pointers and we can look at
    // built-in interpretations of the name
    if (name.ns == null) {
        if (builtins.get(name.local)) |builtin| {
            if (options.nullable and std.mem.startsWith(u8, builtin, "*")) {
                try out.print("?", .{});
            }
            try out.print("$L", .{builtin});
            return;
        }
    }

    // If we've gotten this far, we must have a plain type. The same caveats as
    // explained in the no c_type case apply here, with respect to "GObject
    // context".
    if (options.gobject_context and ctx.isPointerType(name)) {
        if (options.nullable) {
            try out.print("?", .{});
        }
        try out.print("*", .{});
    }
    try translateName(allocator, name, out);
}

test "translateType" {
    try testTranslateType("bool", .{ .name = .{ .ns = null, .local = "gboolean" }, .c_type = "gboolean" }, .{});
    try testTranslateType("bool", .{ .name = .{ .ns = null, .local = "gboolean" }, .c_type = "bool" }, .{});
    try testTranslateType("bool", .{ .name = .{ .ns = null, .local = "gboolean" }, .c_type = "_Bool" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "gchar" }, .c_type = "gchar" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "gchar" }, .c_type = "char" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "guint8" }, .c_type = "guchar" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "guint8" }, .c_type = "unsigned char" }, .{});
    try testTranslateType("i8", .{ .name = .{ .ns = null, .local = "gint8" }, .c_type = "gint8" }, .{});
    try testTranslateType("i8", .{ .name = .{ .ns = null, .local = "gint8" }, .c_type = "int8_t" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "guint8" }, .c_type = "guint8" }, .{});
    try testTranslateType("u8", .{ .name = .{ .ns = null, .local = "guint8" }, .c_type = "uint8_t" }, .{});
    try testTranslateType("i16", .{ .name = .{ .ns = null, .local = "gint16" }, .c_type = "gint16" }, .{});
    try testTranslateType("i16", .{ .name = .{ .ns = null, .local = "gint16" }, .c_type = "int16_t" }, .{});
    try testTranslateType("u16", .{ .name = .{ .ns = null, .local = "guint16" }, .c_type = "guint16" }, .{});
    try testTranslateType("u16", .{ .name = .{ .ns = null, .local = "guint16" }, .c_type = "uint16_t" }, .{});
    try testTranslateType("i32", .{ .name = .{ .ns = null, .local = "gint32" }, .c_type = "gint32" }, .{});
    try testTranslateType("i32", .{ .name = .{ .ns = null, .local = "gint32" }, .c_type = "int32_t" }, .{});
    try testTranslateType("u32", .{ .name = .{ .ns = null, .local = "guint32" }, .c_type = "guint32" }, .{});
    try testTranslateType("u32", .{ .name = .{ .ns = null, .local = "guint32" }, .c_type = "uint32_t" }, .{});
    try testTranslateType("i64", .{ .name = .{ .ns = null, .local = "gint64" }, .c_type = "gint64" }, .{});
    try testTranslateType("i64", .{ .name = .{ .ns = null, .local = "gint64" }, .c_type = "int64_t" }, .{});
    try testTranslateType("u64", .{ .name = .{ .ns = null, .local = "guint64" }, .c_type = "guint64" }, .{});
    try testTranslateType("u64", .{ .name = .{ .ns = null, .local = "guint64" }, .c_type = "uint64_t" }, .{});
    try testTranslateType("c_short", .{ .name = .{ .ns = null, .local = "gshort" }, .c_type = "gshort" }, .{});
    try testTranslateType("c_short", .{ .name = .{ .ns = null, .local = "gshort" }, .c_type = "short" }, .{});
    try testTranslateType("c_ushort", .{ .name = .{ .ns = null, .local = "gushort" }, .c_type = "gushort" }, .{});
    try testTranslateType("c_ushort", .{ .name = .{ .ns = null, .local = "gushort" }, .c_type = "unsigned short" }, .{});
    try testTranslateType("c_int", .{ .name = .{ .ns = null, .local = "gint" }, .c_type = "gint" }, .{});
    try testTranslateType("c_int", .{ .name = .{ .ns = null, .local = "gint" }, .c_type = "int" }, .{});
    try testTranslateType("c_uint", .{ .name = .{ .ns = null, .local = "guint" }, .c_type = "uint" }, .{});
    try testTranslateType("c_uint", .{ .name = .{ .ns = null, .local = "guint" }, .c_type = "unsigned int" }, .{});
    try testTranslateType("c_long", .{ .name = .{ .ns = null, .local = "glong" }, .c_type = "glong" }, .{});
    try testTranslateType("c_long", .{ .name = .{ .ns = null, .local = "glong" }, .c_type = "long" }, .{});
    try testTranslateType("c_long", .{ .name = .{ .ns = null, .local = "glong" }, .c_type = "time_t" }, .{});
    try testTranslateType("c_ulong", .{ .name = .{ .ns = null, .local = "gulong" }, .c_type = "ulong" }, .{});
    try testTranslateType("c_ulong", .{ .name = .{ .ns = null, .local = "gulong" }, .c_type = "unsigned long" }, .{});
    try testTranslateType("usize", .{ .name = .{ .ns = null, .local = "gsize" }, .c_type = "gsize" }, .{});
    try testTranslateType("usize", .{ .name = .{ .ns = null, .local = "gsize" }, .c_type = "size_t" }, .{});
    try testTranslateType("isize", .{ .name = .{ .ns = null, .local = "gssize" }, .c_type = "gssize" }, .{});
    try testTranslateType("isize", .{ .name = .{ .ns = null, .local = "gssize" }, .c_type = "ssize_t" }, .{});
    try testTranslateType("u16", .{ .name = .{ .ns = null, .local = "gunichar2" }, .c_type = "gunichar2" }, .{});
    try testTranslateType("u32", .{ .name = .{ .ns = null, .local = "gunichar" }, .c_type = "gunichar" }, .{});
    try testTranslateType("f32", .{ .name = .{ .ns = null, .local = "gfloat" }, .c_type = "gfloat" }, .{});
    try testTranslateType("f32", .{ .name = .{ .ns = null, .local = "gfloat" }, .c_type = "float" }, .{});
    try testTranslateType("f64", .{ .name = .{ .ns = null, .local = "gdouble" }, .c_type = "gdouble" }, .{});
    try testTranslateType("f64", .{ .name = .{ .ns = null, .local = "gdouble" }, .c_type = "double" }, .{});
    try testTranslateType("c_longdouble", .{ .name = .{ .ns = null, .local = "long double" }, .c_type = "long double" }, .{});
    try testTranslateType("void", .{ .name = .{ .ns = null, .local = "none" }, .c_type = "void" }, .{});
    try testTranslateType("std.builtin.VaList", .{ .name = .{ .ns = null, .local = "va_list" }, .c_type = "va_list" }, .{});
    try testTranslateType("usize", .{ .name = .{ .ns = "GLib", .local = "GType" }, .c_type = "GType" }, .{});
    try testTranslateType("usize", .{ .name = .{ .ns = "GObject", .local = "GType" }, .c_type = "GType" }, .{});
    try testTranslateType("gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" }, .c_type = "GdkEvent" }, .{});
    try testTranslateType("gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{});
    try testTranslateType("gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true });
    try testTranslateType("*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true, .pointer_types = &.{"Gdk.Event"} });
    try testTranslateType("?*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true, .nullable = true, .pointer_types = &.{"Gdk.Event"} });
    try testTranslateType("*anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gpointer" }, .{});
    try testTranslateType("?*anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gpointer" }, .{ .nullable = true });
    try testTranslateType("*const anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gconstpointer" }, .{});
    try testTranslateType("?*const anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gconstpointer" }, .{ .nullable = true });
    try testTranslateType("*anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "void*" }, .{});
    try testTranslateType("?*anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "void*" }, .{ .nullable = true });
    try testTranslateType("*const anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "const void*" }, .{});
    try testTranslateType("?*const anyopaque", .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "const void*" }, .{ .nullable = true });
    try testTranslateType("*glib.Mutex", .{ .name = .{ .ns = "GLib", .local = "Mutex" }, .c_type = "GMutex*" }, .{});
    try testTranslateType("?*glib.Mutex", .{ .name = .{ .ns = "GLib", .local = "Mutex" }, .c_type = "GMutex*" }, .{ .nullable = true });
    try testTranslateType("*gobject.Object", .{ .name = .{ .ns = "GObject", .local = "Object" }, .c_type = "GObject*" }, .{});
    try testTranslateType("?*gobject.Object", .{ .name = .{ .ns = "GObject", .local = "Object" }, .c_type = "GObject*" }, .{ .nullable = true });
    try testTranslateType("*c_longdouble", .{ .name = .{ .ns = null, .local = "long double" }, .c_type = "long double*" }, .{});
    try testTranslateType("?*c_longdouble", .{ .name = .{ .ns = null, .local = "long double" }, .c_type = "long double*" }, .{ .nullable = true });
    try testTranslateType("*std.builtin.VaList", .{ .name = .{ .ns = null, .local = "va_list" }, .c_type = "va_list*" }, .{});
    try testTranslateType("?*std.builtin.VaList", .{ .name = .{ .ns = null, .local = "va_list" }, .c_type = "va_list*" }, .{ .nullable = true });
    // This completely unnecessary const qualifier actually does show up in the
    // GLib GIR (the line parameter of assert_warning)
    try testTranslateType("c_int", .{ .name = .{ .ns = null, .local = "gint" }, .c_type = "const int" }, .{});
    // I hate strings in GIR
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar*" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar*" }, .{ .nullable = true });
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "const gchar*" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "const gchar*" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gchar*" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gchar*" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gchar*" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gchar*" }, .{ .nullable = true });
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const char*" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const char*" }, .{ .nullable = true });
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "const char*" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "const char*" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "char*" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "char*" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "char*" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "char*" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = null }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = null }, .{ .nullable = true });
    // TODO: why is this not an array type in GIR? This inhibits a good translation here.
    // See the invalidated_properties parameter in Gio and similar.
    try testTranslateType("*const [*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar* const*" }, .{});
    try testTranslateType("?*const [*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar* const*" }, .{ .nullable = true });
    // TODO: this is perhaps not ideal, but it's how the C code is written, seemingly for compatibility with using the functions as generic callbacks.
    // Maybe we'll decide we don't care about this and try to do a translation with the proper type.
    try testTranslateType("*anyopaque", .{ .name = .{ .ns = null, .local = "Object" }, .c_type = "gpointer" }, .{});
    try testTranslateType("?*anyopaque", .{ .name = .{ .ns = null, .local = "Object" }, .c_type = "gpointer" }, .{ .nullable = true });
    try testTranslateType("*const anyopaque", .{ .name = .{ .ns = "GLib", .local = "Bytes" }, .c_type = "gconstpointer" }, .{});
    try testTranslateType("?*const anyopaque", .{ .name = .{ .ns = "GLib", .local = "Bytes" }, .c_type = "gconstpointer" }, .{ .nullable = true });
    // We may want to revisit these at some point, or they may just be a lost
    // cause, since the GIR doesn't tell us whether these are really meant to be
    // single or many pointers, and there are examples of both interpretations.
    // This is what C pointers are designed to solve, but GIR should really give us
    // enough information to tell the difference, so it would be a shame to use
    // them. Maybe the usage as a return value or out parameter can help?
    try testTranslateType("*u16", .{ .name = .{ .ns = null, .local = "guint16" }, .c_type = "gunichar2*" }, .{});
    try testTranslateType("?*u16", .{ .name = .{ .ns = null, .local = "guint16" }, .c_type = "gunichar2*" }, .{ .nullable = true });
    try testTranslateType("*const u32", .{ .name = .{ .ns = null, .local = "gunichar" }, .c_type = "const gunichar*" }, .{});
    try testTranslateType("?*const u32", .{ .name = .{ .ns = null, .local = "gunichar" }, .c_type = "const gunichar*" }, .{ .nullable = true });
    // This one has sub-elements (type parameters) in GIR, which we're not
    // currently parsing, and probably never will
    try testTranslateType("*glib.HashTable", .{ .name = .{ .ns = "GLib", .local = "HashTable" }, .c_type = "GHashTable*" }, .{});
    try testTranslateType("?*glib.HashTable", .{ .name = .{ .ns = "GLib", .local = "HashTable" }, .c_type = "GHashTable*" }, .{ .nullable = true });
    // Not ideal, but also not possible to do any better
    try testTranslateType("*anyopaque", .{ .c_type = "_GtkMountOperationHandler*" }, .{});
    try testTranslateType("*const anyopaque", .{ .c_type = "const _GtkMountOperationHandler*" }, .{});
    try testTranslateType("?*anyopaque", .{ .c_type = "_GtkMountOperationHandler*" }, .{ .nullable = true });
    try testTranslateType("?*const anyopaque", .{ .c_type = "const _GtkMountOperationHandler*" }, .{ .nullable = true });
}

const TestTranslateTypeOptions = struct {
    nullable: bool = false,
    gobject_context: bool = false,
    pointer_types: []const []const u8 = &.{},

    fn initTranslationContext(self: TestTranslateTypeOptions, base_allocator: Allocator) !TranslationContext {
        var ctx = TranslationContext.init(base_allocator);
        const allocator = ctx.arena.allocator();
        for (self.pointer_types) |pointer_type| {
            const ns_sep = mem.indexOfScalar(u8, pointer_type, '.').?;
            const ns_name = pointer_type[0..ns_sep];
            const local_name = pointer_type[ns_sep + 1 ..];
            const ns_map = try ctx.namespaces.getOrPut(allocator, ns_name);
            if (!ns_map.found_existing) {
                ns_map.value_ptr.* = .{ .pointer_types = StringHashMapUnmanaged(void){} };
            }
            try ns_map.value_ptr.pointer_types.put(allocator, local_name, {});
        }
        return ctx;
    }

    fn options(self: TestTranslateTypeOptions) TranslateTypeOptions {
        return .{
            .nullable = self.nullable,
            .gobject_context = self.gobject_context,
        };
    }
};

fn testTranslateType(expected: []const u8, @"type": gir.Type, options: TestTranslateTypeOptions) !void {
    var ctx = try options.initTranslationContext(testing.allocator);
    defer ctx.deinit();
    var buf = ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    var out = zigWriter(buf.writer());
    try translateType(testing.allocator, @"type", options.options(), ctx, &out);
    try testing.expectEqualStrings(expected, buf.items);
}

fn translateArrayType(allocator: Allocator, @"type": gir.ArrayType, options: TranslateTypeOptions, ctx: TranslationContext, out: anytype) !void {
    // This special case is useful for types like glib.Array which are
    // translated as array types even though they're not really arrays
    if (@"type".name != null and @"type".c_type != null) {
        return translateType(allocator, .{ .name = @"type".name, .c_type = @"type".c_type }, options, ctx, out);
    }

    var pointer_type: ?CPointerType = null;
    if (@"type".c_type) |original_c_type| {
        var c_type = original_c_type;
        // Translate certain known aliases
        if (std.mem.eql(u8, c_type, "gpointer")) {
            c_type = "void*";
        } else if (std.mem.eql(u8, c_type, "gconstpointer")) {
            c_type = "const void*";
        } else if (std.mem.eql(u8, c_type, "GStrv")) {
            c_type = "gchar**";
        }

        pointer_type = parseCPointerType(c_type);
    }

    if (@"type".fixed_size) |fixed_size| {
        // The fixed-size attribute is interpreted differently based on whether
        // the underlying type is a pointer. If it is not a pointer, we should
        // assume that we're looking at a real fixed-size array (the case at
        // this point in the flow); if it is a pointer, we should assume that
        // we're looking at a pointer to a fixed-size array. GIR is rather
        // confusing in this respect.
        if (pointer_type == null) {
            try out.print("[$L]", .{fixed_size});
        } else {
            // This is a pointer to a fixed-length array; the array details will
            // be written below.
            try out.print("*", .{});
        }
    } else {
        try out.print("[*", .{});
        if (@"type".zero_terminated) {
            const element_is_pointer = blk: {
                if (pointer_type) |pointer| {
                    if (parseCPointerType(pointer.element) != null) {
                        break :blk true;
                    }
                }
                break :blk false;
            };
            if (element_is_pointer) {
                try out.print(":null", .{});
            } else {
                try out.print(":0", .{});
            }
        }
        try out.print("]", .{});
    }

    var element_c_type: ?[]const u8 = null;
    if (pointer_type) |pointer| {
        if (pointer.@"const") {
            try out.print("const ", .{});
        }
        if (@"type".fixed_size) |fixed_size| {
            // This is the other half of the comment above: we're looking at a
            // pointer to a fixed-size array here
            try out.print("[$L]", .{fixed_size});
        }
        element_c_type = pointer.element;
    }

    switch (@"type".element.*) {
        .simple => |element| {
            var modified_element = element;
            modified_element.c_type = element_c_type orelse element.c_type;
            try translateType(allocator, modified_element, .{
                .gobject_context = options.gobject_context,
                .nullable = @"type".zero_terminated,
            }, ctx, out);
        },
        .array => |element| {
            var modified_element = element;
            modified_element.c_type = element_c_type orelse element.c_type;
            try translateArrayType(allocator, modified_element, .{
                .gobject_context = options.gobject_context,
                .nullable = @"type".zero_terminated,
            }, ctx, out);
        },
    }
}

test "translateArrayType" {
    try testTranslateArrayType("[3]*anyopaque", .{
        .fixed_size = 3,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gpointer" },
        },
    }, .{});
    try testTranslateArrayType("[*:0]u8", .{
        .c_type = "gpointer",
        .zero_terminated = true,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "guint8" } },
        },
    }, .{});
    try testTranslateArrayType("[*:0]const u8", .{
        .c_type = "gconstpointer",
        .zero_terminated = true,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "guint8" } },
        },
    }, .{});
    try testTranslateArrayType("*glib.Array", .{
        .name = .{ .ns = "GLib", .local = "Array" },
        .c_type = "GArray*",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "gpointer" }, .c_type = "gpointer" },
        },
    }, .{});
    try testTranslateArrayType("[*][*:0]const u8", .{
        .c_type = "const gchar**",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gchar*" },
        },
    }, .{});
    try testTranslateArrayType("[*][*:0]const u8", .{
        .c_type = "const gchar**",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "filename" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("[*]const u8", .{
        .c_type = "const gchar*",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gchar" },
        },
    }, .{});
    try testTranslateArrayType("[*][*:0]const u8", .{
        .c_type = "const gchar**",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("[*][*:0]u8", .{
        .c_type = "GStrv",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("[*][*:0]u8", .{
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("[*:null]?[*:0]u8", .{
        .c_type = "gchar**",
        .zero_terminated = true,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("*const [4]gdk.RGBA", .{
        .c_type = "const GdkRGBA*",
        .fixed_size = 4,
        .element = &.{
            .simple = .{ .name = .{ .ns = "Gdk", .local = "RGBA" }, .c_type = "GdkRGBA" },
        },
    }, .{});
    try testTranslateArrayType("[2]gobject._Value__data__union", .{
        .fixed_size = 2,
        .element = &.{
            .simple = .{ .name = .{ .ns = "GObject", .local = "_Value__data__union" }, .c_type = null },
        },
    }, .{});
    try testTranslateArrayType("[*]*gio.File", .{
        .c_type = "gpointer",
        .element = &.{
            .simple = .{ .name = .{ .ns = "Gio", .local = "File" }, .c_type = null },
        },
    }, .{ .gobject_context = true, .pointer_types = &.{"Gio.File"} });
}

fn testTranslateArrayType(expected: []const u8, @"type": gir.ArrayType, options: TestTranslateTypeOptions) !void {
    var ctx = try options.initTranslationContext(testing.allocator);
    defer ctx.deinit();
    var buf = ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    var out = zigWriter(buf.writer());
    try translateArrayType(testing.allocator, @"type", options.options(), ctx, &out);
    try testing.expectEqualStrings(expected, buf.items);
}

const CPointerType = struct {
    @"const": bool,
    element: []const u8,
};

// TODO: we should probably parse the type more robustly
fn parseCPointerType(c_type: []const u8) ?CPointerType {
    if (!std.mem.endsWith(u8, c_type, "*")) {
        return null;
    }
    var element = c_type[0 .. c_type.len - "*".len];
    if (std.mem.endsWith(u8, element, " const")) {
        return .{
            .@"const" = true,
            .element = element[0 .. element.len - " const".len],
        };
    }
    if (std.mem.startsWith(u8, element, "const ") and !std.mem.endsWith(u8, element, "*")) {
        return .{
            .@"const" = true,
            .element = element["const ".len..],
        };
    }
    return .{ .@"const" = false, .element = element };
}

fn translateCallback(allocator: Allocator, callback: gir.Callback, named: bool, ctx: TranslationContext, out: anytype) !void {
    // TODO: workaround specific to ClosureNotify until https://github.com/ziglang/zig/issues/12325 is fixed
    if (named and mem.eql(u8, callback.name, "ClosureNotify")) {
        try out.print("pub const ClosureNotify = ?*const fn (p_data: ?*anyopaque, p_closure: *anyopaque) callconv(.C) void;\n\n", .{});
        return;
    }

    if (named) {
        try translateDocumentation(callback.documentation, out);
        try out.print("pub const $I = ", .{callback.name});
    }

    try out.print("?*const fn (", .{});
    try translateParameters(allocator, callback.parameters, .{ .throws = callback.throws }, ctx, out);
    try out.print(") callconv(.C) ", .{});
    const type_options = TranslateTypeOptions{ .nullable = callback.return_value.nullable or callback.throws };
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, type_options, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, type_options, ctx, out),
    }

    if (named) {
        try out.print(";\n\n", .{});
    }
}

const TranslateParametersOptions = struct {
    self_type: []const u8 = "Self",
    gobject_context: bool = false,
    throws: bool = false,
};

fn translateParameters(allocator: Allocator, parameters: []const gir.Parameter, options: TranslateParametersOptions, ctx: TranslationContext, out: anytype) !void {
    for (parameters, 0..) |parameter, i| {
        try translateParameter(allocator, parameter, .{
            .self_type = options.self_type,
            .gobject_context = options.gobject_context,
        }, ctx, out);
        if (options.throws or i < parameters.len - 1) {
            try out.print(", ", .{});
        }
    }
    // Why does GIR encode the presence of a parameter in an attribute outside
    // the parameters element?
    if (options.throws) {
        try out.print("p_error: ?*?*glib.Error", .{});
    }
}

const TranslateParameterOptions = struct {
    self_type: []const u8 = "Self",
    gobject_context: bool = false,
};

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, options: TranslateParameterOptions, ctx: TranslationContext, out: anytype) !void {
    if (parameter.type == .varargs) {
        try out.print("...", .{});
        return;
    }

    try translateParameterName(allocator, parameter.name, out);
    try out.print(": ", .{});
    if (parameter.instance) {
        // TODO: what if the instance parameter isn't a pointer?
        if (parameter.nullable or parameter.optional) {
            try out.print("?", .{});
        }
        if (mem.startsWith(u8, parameter.type.simple.c_type.?, "const ")) {
            try out.print("*const $I", .{options.self_type});
        } else {
            try out.print("*$I", .{options.self_type});
        }
    } else {
        const type_options = TranslateTypeOptions{
            .nullable = parameter.nullable or parameter.optional,
            .gobject_context = options.gobject_context,
        };
        switch (parameter.type) {
            .simple => |simple_type| try translateType(allocator, simple_type, type_options, ctx, out),
            .array => |array_type| try translateArrayType(allocator, array_type, type_options, ctx, out),
            .varargs => unreachable, // handled above
        }
    }
}

const TranslateParameterNamesOptions = struct {
    throws: bool = false,
};

fn translateParameterNames(allocator: Allocator, parameters: []const gir.Parameter, options: TranslateParameterNamesOptions, out: anytype) !void {
    for (parameters, 0..) |parameter, i| {
        try translateParameterName(allocator, parameter.name, out);
        if (options.throws or i < parameters.len - 1) {
            try out.print(", ", .{});
        }
    }
    if (options.throws) {
        try out.print("p_error", .{});
    }
}

fn translateParameterName(allocator: Allocator, parameter_name: []const u8, out: anytype) !void {
    var translated_name = try fmt.allocPrint(allocator, "p_{s}", .{parameter_name});
    defer allocator.free(translated_name);
    try out.print("$I", .{translated_name});
}

const TranslateReturnValueOptions = struct {
    /// Whether the return value should be forced to be nullable. This is
    /// relevant for "throwing" functions, where return values are expected to
    /// be null in case of failure, but for some reason GIR doesn't mark them as
    /// nullable explicitly.
    nullable: bool = false,
    gobject_context: bool = false,
};

fn translateReturnValue(allocator: Allocator, return_value: gir.ReturnValue, options: TranslateReturnValueOptions, ctx: TranslationContext, out: anytype) !void {
    try translateAnyType(allocator, return_value.type, .{
        .nullable = options.nullable or return_value.nullable,
        .gobject_context = options.gobject_context,
    }, ctx, out);
}

fn translateDocumentation(documentation: ?gir.Documentation, out: anytype) !void {
    if (documentation) |doc| {
        var lines = mem.split(u8, doc.text, "\n");
        while (lines.next()) |line| {
            try out.print("/// $L\n", .{line});
        }
    }
}

fn translateName(allocator: Allocator, name: gir.Name, out: anytype) !void {
    try translateNameNs(allocator, name.ns, out);
    try out.print("$I", .{name.local});
}

fn translateNameNs(allocator: Allocator, nameNs: ?[]const u8, out: anytype) !void {
    if (nameNs != null) {
        const type_ns = try ascii.allocLowerString(allocator, nameNs.?);
        defer allocator.free(type_ns);
        try out.print("$I.", .{type_ns});
    }
}

fn toCamelCase(allocator: Allocator, name: []const u8, word_sep: []const u8) ![]u8 {
    var out = ArrayList(u8).init(allocator);
    var words = mem.split(u8, name, word_sep);
    var i: usize = 0;
    while (words.next()) |word| : (i += 1) {
        if (word.len > 0) {
            if (i == 0) {
                try out.appendSlice(word);
            } else {
                try out.append(ascii.toUpper(word[0]));
                try out.appendSlice(word[1..]);
            }
        }
    }
    return out.toOwnedSlice();
}

pub const CreateBuildFileError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn createBuildFile(repositories: *Repositories, out_dir: fs.Dir) !void {
    const allocator = repositories.arena.allocator();

    var repository_map = RepositoryMap.init(allocator);
    defer repository_map.deinit();
    for (repositories.repositories) |repo| {
        try repository_map.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    const file = try out_dir.createFile("build.zig", .{});
    defer file.close();
    var bw = io.bufferedWriter(file.writer());
    var out = zigWriter(bw.writer());

    try out.print(
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) !void ${
        \\
    , .{});

    // Declare all modules (without dependencies, so order won't matter)
    for (repositories.repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);
        try out.print("const $I = b.addModule($S, .{ .source_file = .{ .path = try b.build_root.join(b.allocator, &.{\"src\", \"$L.zig\"}) } });\n", .{ module_name, module_name, module_name });
        try out.print("$I.linkLibC();\n", .{module_name});
        for (repo.packages) |package| {
            try out.print("$I.linkSystemLibrary($S);\n", .{ module_name, package.name });
        }
    }

    // Dependencies
    for (repositories.repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        var seen = HashMap(gir.Include, void, IncludeContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen.deinit();
        var needed_deps = ArrayList(gir.Include).init(allocator);
        defer needed_deps.deinit();
        if (repository_map.get(.{ .name = repo.namespace.name, .version = repo.namespace.version })) |dep_repo| {
            try needed_deps.appendSlice(dep_repo.includes);
        }
        while (needed_deps.popOrNull()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                const dep_module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
                defer allocator.free(dep_module_name);
                const alias = try ascii.allocLowerString(allocator, needed_dep.name);
                defer allocator.free(alias);
                try out.print("try $I.dependencies.put($S, $I);\n", .{ module_name, dep_module_name, dep_module_name });

                try seen.put(needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try needed_deps.appendSlice(dep_repo.includes);
                }
            }
        }
        // The self-dependency is useful for extras files to be able to import their own module by name
        try out.print("try $I.dependencies.put($S, $I);\n", .{ module_name, module_name, module_name });
    }

    try out.print("$}\n", .{});

    try bw.flush();
    try file.sync();
}

test {
    testing.refAllDecls(@This());
}
