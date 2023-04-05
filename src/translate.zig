const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;
const zig = std.zig;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArenaAllocator = heap.ArenaAllocator;
const HashMap = std.HashMap;
const StringHashMap = std.StringHashMap;

const extras = @import("extras.zig");
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

pub const TranslateError = error{
    InvalidExtras,
} || Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

const NamespaceDependencies = HashMap(gir.Include, []const gir.Include, IncludeContext, std.hash_map.default_max_load_percentage);
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

pub fn translate(repositories: *Repositories, extras_dir: fs.Dir, out_dir: fs.Dir) TranslateError!void {
    const allocator = repositories.arena.allocator();

    var deps = NamespaceDependencies.init(allocator);
    defer deps.deinit();
    for (repositories.repositories) |repo| {
        try deps.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo.includes);
    }

    for (repositories.repositories) |repo| {
        const source_name = try fmt.allocPrint(allocator, "{s}-{s}", .{ repo.namespace.name, repo.namespace.version });
        defer allocator.free(source_name);
        const extras_repo = try findExtrasRepository(allocator, source_name, extras_dir);
        try translateRepository(allocator, repo, extras_repo, deps, out_dir);
    }
}

fn findExtrasRepository(allocator: Allocator, name: []const u8, extras_dir: fs.Dir) !?extras.Repository {
    const extras_name = try fmt.allocPrint(allocator, "{s}.gir.extras", .{name});
    defer allocator.free(extras_name);
    const path = realpathAllocZ(allocator, extras_dir, extras_name) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(path);
    return try extras.Repository.parseFile(allocator, path);
}

fn realpathAllocZ(allocator: Allocator, dir: fs.Dir, name: []const u8) ![:0]u8 {
    const path = try dir.realpathAlloc(allocator, name);
    defer allocator.free(path);
    return try allocator.dupeZ(u8, path);
}

fn translateRepository(allocator: Allocator, repo: gir.Repository, maybe_extras_repo: ?extras.Repository, deps: NamespaceDependencies, out_dir: fs.Dir) !void {
    const ns = repo.namespace;
    const file_name = try fileNameAlloc(allocator, ns.name, ns.version);
    defer allocator.free(file_name);
    const file = try out_dir.createFile(file_name, .{});
    defer file.close();
    var bw = io.bufferedWriter(file.writer());
    const out = bw.writer();

    const maybe_extras_ns = if (maybe_extras_repo) |extras_repo| extras_repo.namespace else null;
    if (maybe_extras_ns) |extras_ns| {
        if (extras_ns.documentation) |doc| {
            try translateExtraDocumentation(doc, true, "", out);
            _ = try out.write("\n");
        }
    }

    try translateIncludes(allocator, ns, deps, out);
    try translateNamespace(allocator, ns, maybe_extras_ns, out);

    try bw.flush();
    try file.sync();
}

fn translateIncludes(allocator: Allocator, ns: gir.Namespace, deps: NamespaceDependencies, out: anytype) !void {
    // Having the current namespace in scope using the same name makes type
    // translation logic simpler (no need to know what namespace we're in)
    const ns_lower = try ascii.allocLowerString(allocator, ns.name);
    defer allocator.free(ns_lower);
    try out.print("const {s} = @This();\n\n", .{ns_lower});

    // Including std is also convenient for extra bindings
    _ = try out.write("const std = @import(\"std\");\n");

    var seen = HashMap(gir.Include, void, IncludeContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer seen.deinit();
    var needed_deps = ArrayList(gir.Include).init(allocator);
    defer needed_deps.deinit();
    try needed_deps.appendSlice(deps.get(.{ .name = ns.name, .version = ns.version }) orelse &.{});
    while (needed_deps.popOrNull()) |needed_dep| {
        if (!seen.contains(needed_dep)) {
            const module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
            defer allocator.free(module_name);
            const alias = try ascii.allocLowerString(allocator, needed_dep.name);
            defer allocator.free(alias);
            try out.print("const {s} = @import(\"{s}\");\n", .{ alias, module_name });

            try seen.put(needed_dep, {});
            try needed_deps.appendSlice(deps.get(needed_dep) orelse &.{});
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

fn translateNamespace(allocator: Allocator, ns: gir.Namespace, maybe_extras_ns: ?extras.Namespace, out: anytype) !void {
    var extras_classes = StringHashMap(extras.Class).init(allocator);
    defer extras_classes.deinit();
    var extras_interfaces = StringHashMap(extras.Interface).init(allocator);
    defer extras_interfaces.deinit();
    var extras_records = StringHashMap(extras.Record).init(allocator);
    defer extras_records.deinit();
    if (maybe_extras_ns) |extras_ns| {
        for (extras_ns.classes) |class| {
            try extras_classes.put(class.name, class);
        }
        for (extras_ns.interfaces) |interface| {
            try extras_interfaces.put(interface.name, interface);
        }
        for (extras_ns.records) |record| {
            try extras_records.put(record.name, record);
        }
        for (extras_ns.functions) |function| {
            try translateExtraFunction(function, "", out);
        }
        for (extras_ns.extern_functions) |extern_function| {
            try translateExtraExternFunction(extern_function, "", out);
        }
        for (extras_ns.constants) |constant| {
            try translateExtraConstant(constant, "", out);
        }
        try translateExtraCode(extras_ns.code, "", out);
    }

    for (ns.aliases) |alias| {
        try translateAlias(allocator, alias, out);
    }
    for (ns.classes) |class| {
        try translateClass(allocator, class, extras_classes.get(class.name), out);
    }
    for (ns.interfaces) |interface| {
        try translateInterface(allocator, interface, extras_interfaces.get(interface.name), out);
    }
    for (ns.records) |record| {
        try translateRecord(allocator, record, extras_records.get(record.name), out);
    }
    for (ns.unions) |@"union"| {
        try translateUnion(allocator, @"union", out);
    }
    for (ns.enums) |@"enum"| {
        try translateEnum(allocator, @"enum", out);
    }
    for (ns.bit_fields) |bit_field| {
        try translateBitField(allocator, bit_field, out);
    }
    for (ns.functions) |function| {
        try translateFunction(allocator, function, "", out);
    }
    for (ns.callbacks) |callback| {
        try translateCallback(allocator, callback, true, out);
    }
    for (ns.constants) |constant| {
        try translateConstant(allocator, constant, "", out);
    }
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, out: anytype) !void {
    try translateDocumentation(alias.documentation, "", out);
    try out.print("pub const {s} = ", .{alias.name});
    try translateType(allocator, alias.type, .{}, out);
    _ = try out.write(";\n\n");
}

fn translateClass(allocator: Allocator, class: gir.Class, maybe_extras_class: ?extras.Class, out: anytype) !void {
    // class type
    try translateDocumentation(class.documentation, "", out);
    if (maybe_extras_class) |extras_class| {
        try translateExtraDocumentation(extras_class.documentation, false, "", out);
    }
    try out.print("pub const {s} = ", .{class.name});
    if (class.final) {
        _ = try out.write("opaque {\n");
    } else {
        _ = try out.write("extern struct {\n");
    }

    const parent = class.parent orelse gir.Name{ .ns = "GObject", .local = "TypeInstance" };
    _ = try out.write("    pub const Parent = ");
    try translateNameNs(allocator, parent.ns, out);
    try out.print("{s};\n", .{parent.local});

    _ = try out.write("    pub const Implements = [_]type{");
    for (class.implements, 0..) |implements, i| {
        try translateNameNs(allocator, implements.name.ns, out);
        _ = try out.write(implements.name.local);
        if (i < class.implements.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write("};\n");

    if (class.type_struct) |type_struct| {
        try out.print("    pub const Class = {s};\n", .{type_struct});
    }
    try out.print("    const Self = {s};\n", .{class.name});
    _ = try out.write("\n");

    for (class.fields) |field| {
        try translateField(allocator, field, out);
    }
    if (class.fields.len > 0) {
        _ = try out.write("\n");
    }

    if (maybe_extras_class) |extras_class| {
        for (extras_class.functions) |function| {
            try translateExtraFunction(function, " " ** 4, out);
        }
        for (extras_class.extern_functions) |extern_function| {
            try translateExtraExternFunction(extern_function, " " ** 4, out);
        }
        try translateExtraCode(extras_class.code, " " ** 4, out);
    }

    const get_type_function = class.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, " " ** 4, out);
    }
    for (class.functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }
    if (class.functions.len > 0) {
        _ = try out.write("\n");
    }
    for (class.constructors) |constructor| {
        try translateConstructor(allocator, constructor, " " ** 4, out);
    }
    if (class.constructors.len > 0) {
        _ = try out.write("\n");
    }
    for (class.constants) |constant| {
        try translateConstant(allocator, constant, " " ** 4, out);
    }
    if (class.constants.len > 0) {
        _ = try out.write("\n");
    }
    try out.print("    pub const Methods = {s}Methods;\n", .{class.name});
    _ = try out.write("    pub usingnamespace Methods(Self);\n");
    _ = try out.write("};\n\n");

    // methods mixin
    try out.print("fn {s}Methods(comptime Self: type) type {{\n", .{class.name});
    _ = try out.write("    return struct{\n");
    if (maybe_extras_class) |extras_class| {
        for (extras_class.methods) |method| {
            try translateExtraMethod(method, " " ** 8, out);
        }
        for (extras_class.extern_methods) |extern_method| {
            try translateExtraExternMethod(extern_method, " " ** 8, out);
        }
        try translateExtraCode(extras_class.methods_code, " " ** 8, out);
    }
    for (class.methods) |method| {
        try translateMethod(allocator, method, " " ** 8, out);
    }
    for (class.signals) |signal| {
        try translateSignal(allocator, signal, " " ** 8, out);
    }
    try out.print("        pub usingnamespace {s}.Parent.Methods(Self);\n", .{class.name});
    for (class.implements) |implements| {
        _ = try out.write("        pub usingnamespace ");
        try translateNameNs(allocator, implements.name.ns, out);
        try out.print("{s}.Methods(Self);\n", .{implements.name.local});
    }
    _ = try out.write("    };\n");
    _ = try out.write("}\n\n");

    // virtual methods mixin
    if (class.type_struct) |type_struct| {
        try out.print("fn {s}VirtualMethods(comptime Self: type, comptime Instance: type) type {{\n", .{class.name});
        if (countTranslatableMethods(class.methods) == 0 and class.parent == null) {
            _ = try out.write("    _ = Self;\n");
            _ = try out.write("    _ = Instance;\n");
        }
        _ = try out.write("    return struct{\n");
        for (class.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, type_struct, class.name, " " ** 8, out);
        }
        if (class.parent != null) {
            try out.print("        pub usingnamespace {s}.Parent.Class.VirtualMethods(Self, Instance);\n", .{class.name});
        }
        _ = try out.write("    };\n");
        _ = try out.write("}\n\n");
    }
}

fn translateInterface(allocator: Allocator, interface: gir.Interface, maybe_extras_interface: ?extras.Interface, out: anytype) !void {
    // interface type
    try translateDocumentation(interface.documentation, "", out);
    if (maybe_extras_interface) |extras_interface| {
        try translateExtraDocumentation(extras_interface.documentation, false, "", out);
    }
    try out.print("pub const {s} = opaque {{\n", .{interface.name});

    _ = try out.write("    pub const Prerequisites = [_]type{");
    // This doesn't seem to be correct (since it seems to be possible to create
    // an interface with actually no prerequisites), but it seems to be assumed
    // by GIR documentation generation tools
    if (interface.prerequisites.len == 0) {
        _ = try out.write("gobject.Object");
    }
    for (interface.prerequisites, 0..) |prerequisite, i| {
        try translateNameNs(allocator, prerequisite.name.ns, out);
        _ = try out.write(prerequisite.name.local);
        if (i < interface.prerequisites.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write("};\n");

    if (interface.type_struct) |type_struct| {
        try out.print("    pub const Iface = {s};\n", .{type_struct});
    }
    try out.print("    const Self = {s};\n", .{interface.name});
    _ = try out.write("\n");

    if (maybe_extras_interface) |extras_interface| {
        for (extras_interface.functions) |function| {
            try translateExtraFunction(function, " " ** 4, out);
        }
        for (extras_interface.extern_functions) |extern_function| {
            try translateExtraExternFunction(extern_function, " " ** 4, out);
        }
        try translateExtraCode(extras_interface.code, " " ** 4, out);
    }

    const get_type_function = interface.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, " " ** 4, out);
    }
    for (interface.functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }
    if (interface.functions.len > 0) {
        _ = try out.write("\n");
    }
    for (interface.constructors) |constructor| {
        try translateConstructor(allocator, constructor, " " ** 4, out);
    }
    if (interface.constructors.len > 0) {
        _ = try out.write("\n");
    }
    for (interface.constants) |constant| {
        try translateConstant(allocator, constant, " " ** 4, out);
    }
    if (interface.constants.len > 0) {
        _ = try out.write("\n");
    }
    try out.print("    pub const Methods = {s}Methods;\n", .{interface.name});
    _ = try out.write("    pub usingnamespace Methods(Self);\n");
    _ = try out.write("};\n\n");

    // methods mixin
    try out.print("fn {s}Methods(comptime Self: type) type {{\n", .{interface.name});
    _ = try out.write("    return struct{\n");
    if (maybe_extras_interface) |extras_interface| {
        for (extras_interface.methods) |method| {
            try translateExtraMethod(method, " " ** 8, out);
        }
        for (extras_interface.extern_methods) |extern_method| {
            try translateExtraExternMethod(extern_method, " " ** 8, out);
        }
        try translateExtraCode(extras_interface.methods_code, " " ** 8, out);
    }
    for (interface.methods) |method| {
        try translateMethod(allocator, method, " " ** 8, out);
    }
    for (interface.signals) |signal| {
        try translateSignal(allocator, signal, " " ** 8, out);
    }
    // See the note above on this implicit prerequisite
    if (interface.prerequisites.len == 0) {
        _ = try out.write("        pub usingnamespace gobject.Object.Methods(Self);\n");
    }
    for (interface.prerequisites) |prerequisite| {
        _ = try out.write("        pub usingnamespace ");
        try translateNameNs(allocator, prerequisite.name.ns, out);
        try out.print("{s}.Methods(Self);\n", .{prerequisite.name.local});
    }
    _ = try out.write("    };\n");
    _ = try out.write("}\n\n");

    // virtual methods mixin
    if (interface.type_struct) |type_struct| {
        try out.print("fn {s}VirtualMethods(comptime Self: type, comptime Instance: type) type {{\n", .{interface.name});
        if (interface.virtual_methods.len == 0) {
            _ = try out.write("    _ = Self;\n");
            _ = try out.write("    _ = Instance;\n");
        }
        _ = try out.write("    return struct{\n");
        for (interface.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, type_struct, interface.name, " " ** 8, out);
        }
        _ = try out.write("    };\n");
        _ = try out.write("}\n\n");
    }
}

fn translateRecord(allocator: Allocator, record: gir.Record, maybe_extras_record: ?extras.Record, out: anytype) !void {
    // record type
    try translateDocumentation(record.documentation, "", out);
    if (maybe_extras_record) |extras_record| {
        try translateExtraDocumentation(extras_record.documentation, false, "", out);
    }
    try out.print("pub const {s} = extern struct {{\n", .{record.name});

    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print("    pub const Instance = {s};\n", .{is_gtype_struct_for});
    }
    try out.print("    const Self = {s};\n", .{record.name});
    _ = try out.write("\n");
    for (record.fields) |field| {
        try translateField(allocator, field, out);
    }
    if (record.fields.len > 0) {
        _ = try out.write("\n");
    }

    if (maybe_extras_record) |extras_record| {
        for (extras_record.functions) |function| {
            try translateExtraFunction(function, " " ** 4, out);
        }
        for (extras_record.extern_functions) |extern_function| {
            try translateExtraExternFunction(extern_function, " " ** 4, out);
        }
        try translateExtraCode(extras_record.code, " " ** 4, out);
    }

    if (record.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, " " ** 4, out);
        }
    }
    for (record.functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }
    if (record.functions.len > 0) {
        _ = try out.write("\n");
    }
    for (record.constructors) |constructor| {
        try translateConstructor(allocator, constructor, " " ** 4, out);
    }
    if (record.constructors.len > 0) {
        _ = try out.write("\n");
    }
    try out.print("    pub const Methods = {s}Methods;\n", .{record.name});
    _ = try out.write("    pub usingnamespace Methods(Self);\n");
    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print("    pub const VirtualMethods = {s}VirtualMethods;\n", .{is_gtype_struct_for});
        _ = try out.write("    pub usingnamespace VirtualMethods(Self, Instance);\n");
    }
    _ = try out.write("};\n\n");

    // methods mixin
    try out.print("fn {s}Methods(comptime Self: type) type {{\n", .{record.name});
    if (countTranslatableMethods(record.methods) == 0 and record.is_gtype_struct_for == null and (maybe_extras_record == null or maybe_extras_record.?.methods.len == 0)) {
        _ = try out.write("    _ = Self;\n");
    }
    _ = try out.write("    return struct{\n");
    if (maybe_extras_record) |extras_record| {
        for (extras_record.methods) |method| {
            try translateExtraMethod(method, " " ** 8, out);
        }
        for (extras_record.extern_methods) |extern_method| {
            try translateExtraExternMethod(extern_method, " " ** 8, out);
        }
        try translateExtraCode(extras_record.methods_code, " " ** 8, out);
    }
    for (record.methods) |method| {
        try translateMethod(allocator, method, " " ** 8, out);
    }
    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print(
            \\        const ParentMethods = if (@hasDecl({0s}, "Parent") and @hasDecl({0s}.Parent, "Class"))
            \\            {0s}.Parent.Class.Methods(Self)
            \\        else if (@hasDecl({0s}, "Parent"))
            \\            gobject.TypeClass.Methods(Self)
            \\        else
            \\            struct{{}}
            \\        ;
            \\        pub usingnamespace ParentMethods;
            \\
        , .{is_gtype_struct_for});
    }
    _ = try out.write("    };\n");
    _ = try out.write("}\n\n");
}

fn translateUnion(allocator: Allocator, @"union": gir.Union, out: anytype) !void {
    try translateDocumentation(@"union".documentation, "", out);
    try out.print("pub const {s} = extern union {{\n", .{@"union".name});
    try out.print("    const Self = {s};\n\n", .{@"union".name});
    for (@"union".fields) |field| {
        try translateField(allocator, field, out);
    }
    if (@"union".fields.len > 0) {
        _ = try out.write("\n");
    }
    if (@"union".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, " " ** 4, out);
        }
    }
    for (@"union".functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }
    if (@"union".functions.len > 0) {
        _ = try out.write("\n");
    }
    for (@"union".constructors) |constructor| {
        try translateConstructor(allocator, constructor, " " ** 4, out);
    }
    if (@"union".constructors.len > 0) {
        _ = try out.write("\n");
    }
    for (@"union".methods) |method| {
        try translateMethod(allocator, method, " " ** 4, out);
    }
    _ = try out.write("};\n\n");
}

fn translateField(allocator: Allocator, field: gir.Field, out: anytype) !void {
    try translateDocumentation(field.documentation, " " ** 4, out);
    try out.print("    {}: ", .{zig.fmtId(field.name)});
    try translateFieldType(allocator, field.type, out);
    _ = try out.write(",\n");
}

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, out: anytype) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, .{ .nullable = true }, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{ .nullable = true }, out),
        .callback => |callback| try translateCallback(allocator, callback, false, out),
    }
}

fn translateBitField(allocator: Allocator, bit_field: gir.BitField, out: anytype) !void {
    try translateDocumentation(bit_field.documentation, "", out);
    var paddingNeeded: usize = @bitSizeOf(c_uint);
    try out.print("pub const {s} = packed struct(c_uint) {{\n", .{bit_field.name});
    for (bit_field.members) |member| {
        if (member.value > 0) {
            try out.print("    {s}: bool = false,\n", .{zig.fmtId(member.name)});
            paddingNeeded -= 1;
        }
    }
    if (paddingNeeded > 0) {
        try out.print("    _padding: u{} = 0,\n", .{paddingNeeded});
    }

    try out.print("\n    const Self = {s};\n\n", .{bit_field.name});

    if (bit_field.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, " " ** 4, out);
        }
    }
    for (bit_field.functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }

    _ = try out.write("};\n\n");
}

fn translateEnum(allocator: Allocator, @"enum": gir.Enum, out: anytype) !void {
    try translateDocumentation(@"enum".documentation, "", out);
    try out.print("pub const {s} = enum(c_int) {{\n", .{@"enum".name});
    for (@"enum".members) |member| {
        try out.print("    {s} = {},\n", .{ zig.fmtId(member.name), member.value });
    }

    try out.print("\n    const Self = {s};\n\n", .{@"enum".name});

    if (@"enum".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, " " ** 4, out);
        }
    }
    for (@"enum".functions) |function| {
        try translateFunction(allocator, function, " " ** 4, out);
    }

    _ = try out.write("};\n\n");
}

fn isFunctionTranslatable(function: gir.Function) bool {
    return function.moved_to == null;
}

fn translateFunction(allocator: Allocator, function: gir.Function, indent: []const u8, out: anytype) !void {
    if (!isFunctionTranslatable(function)) {
        return;
    }

    // extern declaration
    try out.print("{s}extern fn {}(", .{ indent, zig.fmtId(function.c_identifier) });
    try translateParameters(allocator, function.parameters, .{ .throws = function.throws }, out);
    _ = try out.write(") ");
    try translateReturnValue(allocator, function.return_value, .{ .nullable = function.throws }, out);
    _ = try out.write(";\n");

    // function rename
    try translateDocumentation(function.documentation, indent, out);
    var fnName = try toCamelCase(allocator, function.name, "_");
    defer allocator.free(fnName);
    try out.print("{s}pub const {} = {};\n\n", .{ indent, zig.fmtId(fnName), zig.fmtId(function.c_identifier) });
}

fn isConstructorTranslatable(constructor: gir.Constructor) bool {
    return constructor.moved_to == null;
}

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, indent: []const u8, out: anytype) !void {
    // TODO: reduce duplication with translateFunction; we need to override the
    // return type here due to many GTK constructors returning just "Widget"
    // instead of their actual type
    if (!isConstructorTranslatable(constructor)) {
        return;
    }

    // extern declaration
    try out.print("{s}extern fn {s}(", .{ indent, zig.fmtId(constructor.c_identifier) });
    try translateParameters(allocator, constructor.parameters, .{ .throws = constructor.throws }, out);
    // TODO: consider if the return value is const, or maybe not even a pointer at all
    _ = try out.write(") callconv(.C) ");
    if (constructor.throws) {
        _ = try out.write("?");
    }
    _ = try out.write("*Self;\n");

    // constructor rename
    try translateDocumentation(constructor.documentation, indent, out);
    var fnName = try toCamelCase(allocator, constructor.name, "_");
    defer allocator.free(fnName);
    try out.print("{s}pub const {s} = {s};\n\n", .{ indent, zig.fmtId(fnName), zig.fmtId(constructor.c_identifier) });
}

fn isMethodTranslatable(method: gir.Method) bool {
    return method.moved_to == null;
}

fn countTranslatableMethods(methods: []const gir.Method) usize {
    var n: usize = 0;
    for (methods) |method| {
        if (isMethodTranslatable(method)) {
            n += 1;
        }
    }
    return n;
}

fn translateMethod(allocator: Allocator, method: gir.Method, indent: []const u8, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = method.name,
        .c_identifier = method.c_identifier,
        .moved_to = method.moved_to,
        .parameters = method.parameters,
        .return_value = method.return_value,
        .throws = method.throws,
        .documentation = method.documentation,
    }, indent, out);
}

fn translateVirtualMethod(allocator: Allocator, virtual_method: gir.VirtualMethod, container_type: []const u8, instance_type: []const u8, indent: []const u8, out: anytype) !void {
    var upper_method_name = try toCamelCase(allocator, virtual_method.name, "_");
    defer allocator.free(upper_method_name);
    if (upper_method_name.len > 0) {
        upper_method_name[0] = ascii.toUpper(upper_method_name[0]);
    }

    // implementation
    try translateDocumentation(virtual_method.documentation, indent, out);
    try out.print("{s}pub fn implement{s}(p_class: *Self, p_implementation: ", .{ indent, upper_method_name });
    try translateVirtualMethodImplementationType(allocator, virtual_method, "Instance", out);
    _ = try out.write(") void {\n");
    try out.print("{s}    @ptrCast(*{s}, p_class).{} = @ptrCast(", .{ indent, container_type, zig.fmtId(virtual_method.name) });
    try translateVirtualMethodImplementationType(allocator, virtual_method, instance_type, out);
    _ = try out.write(", p_implementation);\n");
    try out.print("{s}}}\n\n", .{indent});

    // call
    try out.print("{s}pub fn call{s}(p_class: *Self, ", .{ indent, upper_method_name });
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, out);
    _ = try out.write(") ");
    try translateReturnValue(allocator, virtual_method.return_value, .{ .nullable = virtual_method.throws }, out);
    _ = try out.write(" {\n");
    try out.print("{s}    return @ptrCast(*{s}, p_class).{}.?(", .{ indent, container_type, zig.fmtId(virtual_method.name) });
    try translateParameterNames(allocator, virtual_method.parameters, .{ .throws = virtual_method.throws }, out);
    _ = try out.write(");\n");
    try out.print("{s}}}\n\n", .{indent});
}

fn translateVirtualMethodImplementationType(allocator: Allocator, virtual_method: gir.VirtualMethod, instance_type: []const u8, out: anytype) !void {
    _ = try out.write("*const fn (");
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, out);
    _ = try out.write(") callconv(.C) ");
    try translateReturnValue(allocator, virtual_method.return_value, .{ .nullable = virtual_method.throws }, out);
}

fn translateSignal(allocator: Allocator, signal: gir.Signal, indent: []const u8, out: anytype) !void {
    var upper_signal_name = try toCamelCase(allocator, signal.name, "-");
    defer allocator.free(upper_signal_name);
    if (upper_signal_name.len > 0) {
        upper_signal_name[0] = ascii.toUpper(upper_signal_name[0]);
    }

    // normal connection
    try translateDocumentation(signal.documentation, indent, out);
    try out.print("{s}pub fn connect{s}(p_self: *Self, comptime T: type, p_callback: ", .{ indent, upper_signal_name });
    // TODO: verify that T is a pointer type or compatible
    try translateSignalCallbackType(allocator, signal, out);
    _ = try out.write(", p_data: T, p_options: struct { after: bool = false }) c_ulong {\n");

    try out.print("{s}    return ", .{indent});
    try translateNameNs(allocator, "gobject", out);
    try out.print("signalConnectData(p_self, \"{}\", @ptrCast(", .{zig.fmtEscapes(signal.name)});
    try translateNameNs(allocator, "gobject", out);
    _ = try out.write("Callback, p_callback), p_data, null, .{ .after = p_options.after });\n");

    try out.print("{s}}}\n\n", .{indent});
}

fn translateSignalCallbackType(allocator: Allocator, signal: gir.Signal, out: anytype) !void {
    _ = try out.write("*const fn (*Self");
    if (signal.parameters.len > 0) {
        _ = try out.write(", ");
    }
    try translateParameters(allocator, signal.parameters, .{ .gobject_context = true }, out);
    _ = try out.write(", T) callconv(.C) ");
    try translateReturnValue(allocator, signal.return_value, .{ .gobject_context = true }, out);
}

fn translateConstant(allocator: Allocator, constant: gir.Constant, indent: []const u8, out: anytype) !void {
    // TODO: it would be more idiomatic to use lowercase constant names, but
    // there are way too many constant pairs which differ only in case, especially
    // the names of keyboard keys (e.g. KEY_A and KEY_a in GDK). There is
    // probably some heuristic we can use to at least lowercase most of them.
    try translateDocumentation(constant.documentation, indent, out);
    try out.print("{s}pub const {s}: ", .{ indent, zig.fmtId(constant.name) });
    try translateAnyType(allocator, constant.type, .{}, out);
    _ = try out.write(" = ");
    if (constant.type == .simple and constant.type.simple.name != null and mem.eql(u8, constant.type.simple.name.?.local, "utf8")) {
        try out.print("\"{}\"", .{zig.fmtEscapes(constant.value)});
    } else {
        _ = try out.write(constant.value);
    }
    _ = try out.write(";\n\n");
}

const builtins = std.ComptimeStringMap([]const u8, .{
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

fn translateAnyType(allocator: Allocator, @"type": gir.AnyType, options: TranslateTypeOptions, out: anytype) !void {
    switch (@"type") {
        .simple => |simple| try translateType(allocator, simple, options, out),
        .array => |array| try translateArrayType(allocator, array, options, out),
    }
}

fn translateType(allocator: Allocator, @"type": gir.Type, options: TranslateTypeOptions, out: anytype) TranslateError!void {
    const name = @"type".name orelse {
        _ = try out.write("@compileError(\"unnamed type not understood\")");
        return;
    };
    var c_type = @"type".c_type orelse {
        // We should check for builtins first; utf8 is a common type to end up with here
        if (builtins.get(name.local)) |builtin| {
            if (options.nullable and (std.mem.startsWith(u8, builtin, "*") or std.mem.startsWith(u8, builtin, "[*"))) {
                _ = try out.write("?");
            }
            _ = try out.write(builtin);
            return;
        }

        // At this point, the only thing we can do is assume a plain type.
        if (options.gobject_context) {
            if (options.nullable) {
                _ = try out.write("?");
            }
            _ = try out.write("*");
        }
        try translateNameNs(allocator, name.ns, out);
        _ = try out.write(name.local);
        return;
    };

    // The c_type is more reliable than name when looking for builtins, since
    // the name often does not include any information about whether the type is
    // a pointer
    if (builtins.get(c_type)) |builtin| {
        if (options.nullable and (std.mem.startsWith(u8, builtin, "*") or std.mem.startsWith(u8, builtin, "[*"))) {
            _ = try out.write("?");
        }
        _ = try out.write(builtin);
        return;
    }

    if (parseCPointerType(c_type)) |pointer| {
        if (options.nullable) {
            _ = try out.write("?");
        }
        // Special case: utf8 and filename should be treated as C strings
        if (name.ns == null and (std.mem.eql(u8, name.local, "utf8") or std.mem.eql(u8, name.local, "filename")) and parseCPointerType(pointer.element) == null) {
            _ = try out.write("[*:0]");
        } else {
            _ = try out.write("*");
        }
        if (pointer.@"const") {
            _ = try out.write("const ");
        }
        // Nullability does not apply recursively.
        // TODO: how does GIR expect to represent nullability more than one level deep?
        return translateType(allocator, .{ .name = name, .c_type = pointer.element }, .{ .gobject_context = options.gobject_context }, out);
    }

    // Unnecessary const qualifier for non-pointer type
    if (std.mem.startsWith(u8, c_type, "const ")) {
        c_type = c_type["const ".len..];
        return translateType(allocator, .{ .name = name, .c_type = c_type }, options, out);
    }

    // At this point, we've exhausted explicit pointers and we can look at
    // built-in interpretations of the name
    if (name.ns == null) {
        if (builtins.get(name.local)) |builtin| {
            if (options.nullable and std.mem.startsWith(u8, builtin, "*")) {
                _ = try out.write("?");
            }
            _ = try out.write(builtin);
            return;
        }
    }

    // If we've gotten this far, we must have a plain type
    try translateNameNs(allocator, name.ns, out);
    _ = try out.write(name.local);
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
    try testTranslateType("*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true });
    try testTranslateType("?*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true, .nullable = true });
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
}

fn testTranslateType(expected: []const u8, @"type": gir.Type, options: TranslateTypeOptions) !void {
    var buf = ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    const out = buf.writer();
    try translateType(testing.allocator, @"type", options, out);
    try testing.expectEqualStrings(expected, buf.items);
}

fn translateArrayType(allocator: Allocator, @"type": gir.ArrayType, options: TranslateTypeOptions, out: anytype) !void {
    // This special case is useful for types like glib.Array which are
    // translated as array types even though they're not really arrays
    if (@"type".name != null and @"type".c_type != null) {
        return translateType(allocator, .{ .name = @"type".name, .c_type = @"type".c_type }, options, out);
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
            try out.print("[{}]", .{fixed_size});
        } else {
            // This is a pointer to a fixed-length array; the array details will
            // be written below.
            _ = try out.write("*");
        }
    } else {
        _ = try out.write("[*");
        if (@"type".zero_terminated) {
            _ = try out.write(":0");
        }
        _ = try out.write("]");
    }

    var element_c_type: ?[]const u8 = null;
    if (pointer_type) |pointer| {
        if (pointer.@"const") {
            _ = try out.write("const ");
        }
        if (@"type".fixed_size) |fixed_size| {
            // This is the other half of the comment above: we're looking at a
            // pointer to a fixed-size array here
            try out.print("[{}]", .{fixed_size});
        }
        element_c_type = pointer.element;
    }

    switch (@"type".element.*) {
        .simple => |element| {
            var modified_element = element;
            modified_element.c_type = element_c_type orelse element.c_type;
            try translateType(allocator, modified_element, .{ .gobject_context = options.gobject_context }, out);
        },
        .array => |element| {
            var modified_element = element;
            modified_element.c_type = element_c_type orelse element.c_type;
            try translateArrayType(allocator, modified_element, .{ .gobject_context = options.gobject_context }, out);
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
}

fn testTranslateArrayType(expected: []const u8, @"type": gir.ArrayType, options: TranslateTypeOptions) !void {
    var buf = ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    const out = buf.writer();
    try translateArrayType(testing.allocator, @"type", options, out);
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

fn translateCallback(allocator: Allocator, callback: gir.Callback, named: bool, out: anytype) !void {
    // TODO: workaround specific to ClosureNotify until https://github.com/ziglang/zig/issues/12325 is fixed
    if (named and mem.eql(u8, callback.name, "ClosureNotify")) {
        _ = try out.write("pub const ClosureNotify = ?*const fn (p_data: ?*anyopaque, p_closure: *anyopaque) callconv(.C) void;\n\n");
        return;
    }

    if (named) {
        try translateDocumentation(callback.documentation, "", out);
        try out.print("pub const {s} = ", .{callback.name});
    }

    _ = try out.write("?*const fn (");
    try translateParameters(allocator, callback.parameters, .{ .throws = callback.throws }, out);
    _ = try out.write(") callconv(.C) ");
    const type_options = TranslateTypeOptions{ .nullable = callback.return_value.nullable };
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, type_options, out),
        .array => |array_type| try translateArrayType(allocator, array_type, type_options, out),
    }

    if (named) {
        _ = try out.write(";\n\n");
    }
}

const TranslateParametersOptions = struct {
    self_type: []const u8 = "Self",
    gobject_context: bool = false,
    throws: bool = false,
};

fn translateParameters(allocator: Allocator, parameters: []const gir.Parameter, options: TranslateParametersOptions, out: anytype) !void {
    for (parameters, 0..) |parameter, i| {
        try translateParameter(allocator, parameter, .{
            .self_type = options.self_type,
            .gobject_context = options.gobject_context,
        }, out);
        if (options.throws or i < parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    // Why does GIR encode the presence of a parameter in an attribute outside
    // the parameters element?
    if (options.throws) {
        _ = try out.write("p_error: ?*?*glib.Error");
    }
}

const TranslateParameterOptions = struct {
    self_type: []const u8 = "Self",
    gobject_context: bool = false,
};

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, options: TranslateParameterOptions, out: anytype) !void {
    if (parameter.type == .varargs) {
        _ = try out.write("...");
        return;
    }

    try translateParameterName(allocator, parameter.name, out);
    _ = try out.write(": ");
    if (parameter.instance) {
        // TODO: what if the instance parameter isn't a pointer?
        if (mem.startsWith(u8, parameter.type.simple.c_type.?, "const ")) {
            try out.print("*const {s}", .{options.self_type});
        } else {
            try out.print("*{s}", .{options.self_type});
        }
    } else {
        const type_options = TranslateTypeOptions{
            .nullable = parameter.nullable or parameter.optional,
            .gobject_context = options.gobject_context,
        };
        switch (parameter.type) {
            .simple => |simple_type| try translateType(allocator, simple_type, type_options, out),
            .array => |array_type| try translateArrayType(allocator, array_type, type_options, out),
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
            _ = try out.write(", ");
        }
    }
    if (options.throws) {
        _ = try out.write("p_error");
    }
}

fn translateParameterName(allocator: Allocator, parameter_name: []const u8, out: anytype) !void {
    var translated_name = try fmt.allocPrint(allocator, "p_{s}", .{parameter_name});
    defer allocator.free(translated_name);
    try out.print("{s}", .{zig.fmtId(translated_name)});
}

const TranslateReturnValueOptions = struct {
    /// Whether the return value should be forced to be nullable. This is
    /// relevant for "throwing" functions, where return values are expected to
    /// be null in case of failure, but for some reason GIR doesn't mark them as
    /// nullable explicitly.
    nullable: bool = false,
    gobject_context: bool = false,
};

fn translateReturnValue(allocator: Allocator, return_value: gir.ReturnValue, options: TranslateReturnValueOptions, out: anytype) !void {
    try translateAnyType(allocator, return_value.type, .{
        .nullable = options.nullable or return_value.nullable,
        .gobject_context = options.gobject_context,
    }, out);
}

fn translateDocumentation(documentation: ?gir.Documentation, indent: []const u8, out: anytype) !void {
    if (documentation) |doc| {
        var lines = mem.split(u8, doc.text, "\n");
        while (lines.next()) |line| {
            try out.print("{s}/// {s}\n", .{ indent, line });
        }
    }
}

fn translateNameNs(allocator: Allocator, nameNs: ?[]const u8, out: anytype) !void {
    if (nameNs != null) {
        const type_ns = try ascii.allocLowerString(allocator, nameNs.?);
        defer allocator.free(type_ns);
        try out.print("{s}.", .{type_ns});
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

fn translateExtraFunction(function: extras.Function, indent: []const u8, out: anytype) !void {
    try translateExtraDocumentation(function.documentation, false, indent, out);
    _ = try out.write(indent);
    if (!function.private) {
        _ = try out.write("pub ");
    }
    try out.print("fn {}(", .{zig.fmtId(function.name)});
    try translateExtraParameters(function.parameters, out);
    try out.print(") {s} {{\n", .{function.return_value.type});

    var lines = mem.split(u8, function.body, "\n");
    while (lines.next()) |line| {
        try out.print("{s}    {s}\n", .{ indent, line });
    }

    try out.print("{s}}}\n\n", .{indent});
}

fn translateExtraExternFunction(extern_function: extras.ExternFunction, indent: []const u8, out: anytype) !void {
    // extern declaration
    try out.print("{s}extern fn {}(", .{ indent, zig.fmtId(extern_function.identifier) });
    try translateExtraParameters(extern_function.parameters, out);
    try out.print(") {s};\n", .{extern_function.return_value.type});

    // function rename
    try translateExtraDocumentation(extern_function.documentation, false, indent, out);
    try out.print("{s}pub const {} = {};\n\n", .{ indent, zig.fmtId(extern_function.name), zig.fmtId(extern_function.identifier) });
}

fn translateExtraMethod(method: extras.Method, indent: []const u8, out: anytype) !void {
    try translateExtraFunction(.{
        .name = method.name,
        .parameters = method.parameters,
        .return_value = method.return_value,
        .body = method.body,
        .private = method.private,
        .documentation = method.documentation,
    }, indent, out);
}

fn translateExtraExternMethod(extern_method: extras.ExternMethod, indent: []const u8, out: anytype) !void {
    try translateExtraExternFunction(.{
        .name = extern_method.name,
        .identifier = extern_method.identifier,
        .parameters = extern_method.parameters,
        .return_value = extern_method.return_value,
        .documentation = extern_method.documentation,
    }, indent, out);
}

fn translateExtraParameters(parameters: []const extras.Parameter, out: anytype) !void {
    for (parameters, 0..) |parameter, i| {
        if (parameter.@"comptime") {
            _ = try out.write("comptime ");
        }
        try out.print("{}: {s}", .{ zig.fmtId(parameter.name), parameter.type });
        if (i < parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
}

fn translateExtraConstant(constant: extras.Constant, indent: []const u8, out: anytype) !void {
    try translateExtraDocumentation(constant.documentation, false, indent, out);
    _ = try out.write(indent);
    if (!constant.private) {
        _ = try out.write("pub ");
    }
    try out.print("const {}", .{zig.fmtId(constant.name)});
    if (constant.type) |@"type"| {
        try out.print(": {s}", .{@"type"});
    }
    _ = try out.write(" = ");

    var lines = mem.split(u8, constant.value, "\n");
    var i: usize = 0;
    while (lines.next()) |line| : (i += 1) {
        if (i > 0) {
            try out.print("\n{s}", .{indent});
        }
        try out.print("{s}", .{line});
    }

    _ = try out.write(";\n\n");
}

fn translateExtraDocumentation(documentation: ?extras.Documentation, container: bool, indent: []const u8, out: anytype) !void {
    if (documentation) |doc| {
        var lines = mem.split(u8, doc.text, "\n");
        while (lines.next()) |line| {
            if (container) {
                try out.print("{s}//! {s}\n", .{ indent, line });
            } else {
                try out.print("{s}/// {s}\n", .{ indent, line });
            }
        }
    }
}

fn translateExtraCode(maybe_code: ?extras.Code, indent: []const u8, out: anytype) !void {
    if (maybe_code) |code| {
        var lines = mem.split(u8, code.text, "\n");
        while (lines.next()) |line| {
            try out.print("{s}{s}\n", .{ indent, line });
        }
    }
}

pub const CreateBuildFileError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn createBuildFile(repositories: *Repositories, out_dir: fs.Dir) !void {
    const allocator = repositories.arena.allocator();

    var deps = NamespaceDependencies.init(allocator);
    defer deps.deinit();
    for (repositories.repositories) |repo| {
        try deps.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo.includes);
    }

    const file = try out_dir.createFile("build.zig", .{});
    defer file.close();
    var bw = io.bufferedWriter(file.writer());
    const out = bw.writer();

    _ = try out.write(
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) !void {
        \\
    );

    // Declare all modules (without dependencies, so order won't matter)
    for (repositories.repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);
        try out.print("    const {} = b.addModule(\"{}\", .{{ .source_file = .{{ .path = try b.build_root.join(b.allocator, &.{{\"src\", \"{}.zig\"}}) }} }});\n", .{ zig.fmtId(module_name), zig.fmtEscapes(module_name), zig.fmtEscapes(module_name) });
        try out.print("    {}.linkLibC();\n", .{zig.fmtId(module_name)});
        for (repo.packages) |package| {
            try out.print("    {}.linkSystemLibrary(\"{}\");\n", .{ zig.fmtId(module_name), zig.fmtEscapes(package.name) });
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
        try needed_deps.appendSlice(deps.get(.{ .name = repo.namespace.name, .version = repo.namespace.version }) orelse &.{});
        while (needed_deps.popOrNull()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                const dep_module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
                defer allocator.free(dep_module_name);
                const alias = try ascii.allocLowerString(allocator, needed_dep.name);
                defer allocator.free(alias);
                try out.print("    try {}.dependencies.put(\"{}\", {});\n", .{ zig.fmtId(module_name), zig.fmtEscapes(dep_module_name), zig.fmtId(dep_module_name) });

                try seen.put(needed_dep, {});
                try needed_deps.appendSlice(deps.get(needed_dep) orelse &.{});
            }
        }
    }

    _ = try out.write("}\n");

    try bw.flush();
    try file.sync();
}

test {
    testing.refAllDecls(@This());
}
