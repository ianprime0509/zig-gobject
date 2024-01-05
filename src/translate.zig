const std = @import("std");
const zigWriter = @import("zig_writer.zig").zigWriter;
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const zig = std.zig;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const ArenaAllocator = heap.ArenaAllocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const ComptimeStringMap = std.ComptimeStringMap;
const HashMapUnmanaged = std.HashMapUnmanaged;
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;

const gir = @import("gir.zig");

const RepositoryMap = HashMapUnmanaged(gir.Include, gir.Repository, gir.Include.Context, std.hash_map.default_max_load_percentage);
const RepositorySet = HashMapUnmanaged(gir.Include, void, gir.Include.Context, std.hash_map.default_max_load_percentage);

const TranslationContext = struct {
    namespaces: StringHashMapUnmanaged(Namespace),
    arena: ArenaAllocator,

    fn init(allocator: Allocator) TranslationContext {
        const arena = ArenaAllocator.init(allocator);
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
        var seen = RepositorySet{};
        defer seen.deinit(allocator);
        var needed_deps = ArrayListUnmanaged(gir.Include){};
        defer needed_deps.deinit(allocator);
        try needed_deps.append(allocator, .{ .name = repository.namespace.name, .version = repository.namespace.version });
        while (needed_deps.popOrNull()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                try seen.put(allocator, needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try self.addRepository(dep_repo);
                    try needed_deps.appendSlice(allocator, dep_repo.includes);
                }
            }
        }
    }

    fn addRepository(self: *TranslationContext, repository: gir.Repository) !void {
        const allocator = self.arena.allocator();

        var aliases: StringHashMapUnmanaged(gir.Alias) = .{};
        for (repository.namespace.aliases) |alias| {
            try aliases.put(allocator, alias.name, alias);
        }
        var classes: StringHashMapUnmanaged(gir.Class) = .{};
        for (repository.namespace.classes) |class| {
            try classes.put(allocator, class.name, class);
        }
        var interfaces: StringHashMapUnmanaged(gir.Interface) = .{};
        for (repository.namespace.interfaces) |interface| {
            try interfaces.put(allocator, interface.name, interface);
        }
        var records: StringHashMapUnmanaged(gir.Record) = .{};
        for (repository.namespace.records) |record| {
            try records.put(allocator, record.name, record);
        }
        var unions: StringHashMapUnmanaged(gir.Union) = .{};
        for (repository.namespace.unions) |@"union"| {
            try unions.put(allocator, @"union".name, @"union");
        }
        var bit_fields: StringHashMapUnmanaged(gir.BitField) = .{};
        for (repository.namespace.bit_fields) |bit_field| {
            try bit_fields.put(allocator, bit_field.name, bit_field);
        }
        var enums: StringHashMapUnmanaged(gir.Enum) = .{};
        for (repository.namespace.enums) |@"enum"| {
            try enums.put(allocator, @"enum".name, @"enum");
        }
        var functions: StringHashMapUnmanaged(gir.Function) = .{};
        for (repository.namespace.functions) |function| {
            try functions.put(allocator, function.name, function);
        }
        var callbacks: StringHashMapUnmanaged(gir.Callback) = .{};
        for (repository.namespace.callbacks) |callback| {
            try callbacks.put(allocator, callback.name, callback);
        }
        var constants: StringHashMapUnmanaged(gir.Constant) = .{};
        for (repository.namespace.constants) |constant| {
            try constants.put(allocator, constant.name, constant);
        }

        try self.namespaces.put(allocator, repository.namespace.name, .{
            .name = repository.namespace.name,
            .version = repository.namespace.version,
            .aliases = aliases,
            .classes = classes,
            .interfaces = interfaces,
            .records = records,
            .unions = unions,
            .bit_fields = bit_fields,
            .enums = enums,
            .functions = functions,
            .callbacks = callbacks,
            .constants = constants,
        });
    }

    /// Returns whether the type with the given name is "object-like" in a
    /// GObject context. See the comment in `TranslateTypeOptions` for what
    /// "GObject context" means.
    fn isObjectType(self: TranslationContext, name: gir.Name) bool {
        if (name.ns) |ns| {
            const namespace = self.namespaces.get(ns) orelse return false;
            return namespace.classes.get(name.local) != null or
                namespace.interfaces.get(name.local) != null or
                namespace.records.get(name.local) != null or
                namespace.unions.get(name.local) != null;
        }
        return false;
    }

    /// Returns whether the type with the given name is actually a pointer
    /// (for example, a typedefed pointer). This mostly affects the translation
    /// of nullability (explicit or implied) for the type.
    fn isPointerType(self: TranslationContext, name: gir.Name) bool {
        if (name.ns) |ns| {
            const namespace = self.namespaces.get(ns) orelse return false;
            return (if (namespace.records.get(name.local)) |record| record.isPointer() else false) or
                namespace.callbacks.get(name.local) != null;
        }
        return false;
    }

    const Namespace = struct {
        name: []const u8,
        version: []const u8,
        aliases: StringHashMapUnmanaged(gir.Alias),
        classes: StringHashMapUnmanaged(gir.Class),
        interfaces: StringHashMapUnmanaged(gir.Interface),
        records: StringHashMapUnmanaged(gir.Record),
        unions: StringHashMapUnmanaged(gir.Union),
        bit_fields: StringHashMapUnmanaged(gir.BitField),
        enums: StringHashMapUnmanaged(gir.Enum),
        functions: StringHashMapUnmanaged(gir.Function),
        callbacks: StringHashMapUnmanaged(gir.Callback),
        constants: StringHashMapUnmanaged(gir.Constant),
    };
};

pub const CreateBindingsError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || fs.Dir.CopyFileError || error{
    FileSystem,
    NotSupported,
};

pub fn createBindings(allocator: Allocator, repositories: []const gir.Repository, extras_path: []const fs.Dir, output_dir: fs.Dir) CreateBindingsError!void {
    var repository_map = RepositoryMap{};
    defer repository_map.deinit(allocator);
    for (repositories) |repo| {
        try repository_map.put(allocator, .{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    for (repositories) |repo| {
        const extras_file = try copyExtrasFile(allocator, repo.namespace.name, repo.namespace.version, extras_path, output_dir);
        defer allocator.free(extras_file);
        var ctx = TranslationContext.init(allocator);
        defer ctx.deinit();
        try ctx.addRepositoryAndDependencies(repo, repository_map);
        try translateRepository(allocator, repo, extras_file, repository_map, ctx, output_dir);
    }
}

fn copyExtrasFile(allocator: Allocator, name: []const u8, version: []const u8, extras_path: []const fs.Dir, output_dir: fs.Dir) ![]u8 {
    const extras_name = try extrasFileNameAlloc(allocator, name, version);
    errdefer allocator.free(extras_name);
    for (extras_path) |extras_dir| {
        extras_dir.copyFile(extras_name, output_dir, extras_name, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        return extras_name;
    }
    try output_dir.writeFile(extras_name, "");
    return extras_name;
}

fn extrasFileNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    const file_name = try fmt.allocPrint(allocator, "{s}-{s}.extras.zig", .{ name, version });
    _ = ascii.lowerString(file_name, file_name);
    return file_name;
}

fn translateRepository(allocator: Allocator, repo: gir.Repository, extras_path: []const u8, repository_map: RepositoryMap, ctx: TranslationContext, output_dir: fs.Dir) !void {
    var raw_source = ArrayListUnmanaged(u8){};
    defer raw_source.deinit(allocator);
    var out = zigWriter(raw_source.writer(allocator));

    try out.print("const extras = @import($S);\n", .{extras_path});

    try translateIncludes(allocator, repo.namespace, repository_map, &out);
    try translateNamespace(allocator, repo.namespace, ctx, &out);

    try raw_source.append(allocator, 0);
    var ast = try zig.Ast.parse(allocator, raw_source.items[0 .. raw_source.items.len - 1 :0], .zig);
    defer ast.deinit(allocator);
    const fmt_source = try ast.render(allocator);
    defer allocator.free(fmt_source);
    const file_name = try fileNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
    defer allocator.free(file_name);
    try output_dir.writeFile(file_name, fmt_source);
}

fn translateIncludes(allocator: Allocator, ns: gir.Namespace, repository_map: RepositoryMap, out: anytype) !void {
    // Having the current namespace in scope using the same name makes type
    // translation logic simpler (no need to know what namespace we're in)
    const ns_lower = try ascii.allocLowerString(allocator, ns.name);
    defer allocator.free(ns_lower);
    try out.print("const $I = @This();\n\n", .{ns_lower});

    // std is needed for std.builtin.VaList
    try out.print("const std = @import(\"std\");\n", .{});

    var seen = RepositorySet{};
    defer seen.deinit(allocator);
    var needed_deps = ArrayListUnmanaged(gir.Include){};
    defer needed_deps.deinit(allocator);
    if (repository_map.get(.{ .name = ns.name, .version = ns.version })) |dep_repo| {
        try needed_deps.appendSlice(allocator, dep_repo.includes);
    }
    while (needed_deps.popOrNull()) |needed_dep| {
        if (!seen.contains(needed_dep)) {
            const module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
            defer allocator.free(module_name);
            const alias = try ascii.allocLowerString(allocator, needed_dep.name);
            defer allocator.free(alias);
            try out.print("const $I = @import($S);\n", .{ alias, module_name });

            try seen.put(allocator, needed_dep, {});
            if (repository_map.get(needed_dep)) |dep_repo| {
                try needed_deps.appendSlice(allocator, dep_repo.includes);
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
        try translateFunction(allocator, function, .{}, ctx, out);
    }
    for (ns.callbacks) |callback| {
        try translateCallback(allocator, callback, .{ .named = true }, ctx, out);
    }
    for (ns.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("pub usingnamespace if (@hasDecl(extras, \"namespace\")) extras.namespace else struct {};\n", .{});
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(alias.documentation, out);
    try out.print("pub const $I = ", .{escapeTypeName(alias.name)});
    try translateType(allocator, alias.type, .{}, ctx, out);
    try out.print(";\n\n", .{});
}

fn translateClass(allocator: Allocator, class: gir.Class, ctx: TranslationContext, out: anytype) !void {
    // class type
    try translateDocumentation(class.documentation, out);
    try out.print("pub const $I = ", .{escapeTypeName(class.name)});
    if (class.isOpaque()) {
        try out.print("opaque {\n", .{});
    } else {
        try out.print("extern struct {\n", .{});
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
        try out.print("pub const Class = ", .{});
        try translateName(allocator, type_struct, out);
        try out.print(";\n", .{});
    }
    try out.print("const _Self = @This();\n\n", .{});

    if (!class.isOpaque()) {
        try translateLayoutElements(allocator, class.layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct{\n", .{});
    const get_type_function = class.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (class.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (class.constructors) |constructor| {
        try translateConstructor(allocator, constructor, .{ .self_type = "_Self" }, ctx, out);
    }
    for (class.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("};\n\n", .{});

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
    try out.print("pub usingnamespace Methods(_Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime _Self: type) type {\n", .{class.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = _Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct{\n", .{});
    for (class.methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = "_Self" }, ctx, out);
    }
    for (class.signals) |signal| {
        try translateSignal(allocator, signal, ctx, out);
    }
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LMethods(comptime _Self: type) type {\n", .{class.name});
    try out.print("return struct{\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(_Self);\n", .{class.name});
    try out.print("pub usingnamespace $I.Parent.Methods(_Self);\n", .{escapeTypeName(class.name)});
    for (class.implements) |implements| {
        try out.print("pub usingnamespace ", .{});
        try translateName(allocator, implements.name, out);
        try out.print(".Methods(_Self);\n", .{});
    }
    try out.print("pub usingnamespace $LExtraMethods(_Self);\n", .{class.name});
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime _Self: type) type {\n", .{class.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(_Self) else struct {};\n", .{ class.name, class.name });
    try out.print("}\n\n", .{});

    // virtual methods mixins
    if (class.type_struct) |type_struct| {
        try out.print("fn $LOwnVirtualMethods(comptime _Class: type, comptime _Instance: type) type {\n", .{class.name});
        try out.print(
            \\const _i_dont_care_if_Class_is_unused = _Class;
            \\_ = _i_dont_care_if_Class_is_unused;
            \\const _i_dont_care_if_Instance_is_unused = _Instance;
            \\_ = _i_dont_care_if_Instance_is_unused;
            \\
        , .{});
        try out.print("return struct{\n", .{});
        for (class.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, "_Class", type_struct, class.name, ctx, out);
        }
        try out.print("};\n", .{});
        try out.print("}\n\n", .{});

        try out.print("fn $LVirtualMethods(comptime _Class: type, comptime _Instance: type) type {\n", .{class.name});
        try out.print("return struct{\n", .{});
        try out.print("pub usingnamespace $LOwnVirtualMethods(_Class, _Instance);\n", .{class.name});
        if (class.parent != null) {
            try out.print("pub usingnamespace if (@hasDecl($I.Parent, \"VirtualMethods\")) $I.Parent.VirtualMethods(_Class, _Instance) else struct {};\n", .{ escapeTypeName(class.name), escapeTypeName(class.name) });
        }
        try out.print("pub usingnamespace $LExtraVirtualMethods(_Class, _Instance);\n", .{class.name});
        try out.print("};\n", .{});
        try out.print("}\n\n", .{});

        try out.print("fn $LExtraVirtualMethods(comptime _Class: type, comptime _Instance: type) type {\n", .{class.name});
        try out.print("return if (@hasDecl(extras, \"$LVirtualMethods\")) extras.$LVirtualMethods(_Class, _Instance) else struct {};\n", .{ class.name, class.name });
        try out.print("}\n\n", .{});
    }
}

fn translateInterface(allocator: Allocator, interface: gir.Interface, ctx: TranslationContext, out: anytype) !void {
    // interface type
    try translateDocumentation(interface.documentation, out);
    try out.print("pub const $I = opaque {\n", .{escapeTypeName(interface.name)});

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
        try out.print("pub const Iface = ", .{});
        try translateName(allocator, type_struct, out);
        try out.print(";\n", .{});
    }
    try out.print("const _Self = @This();\n\n", .{});

    try out.print("pub const Own = struct{\n", .{});
    const get_type_function = interface.getTypeFunction();
    if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
        try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (interface.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (interface.constructors) |constructor| {
        try translateConstructor(allocator, constructor, .{ .self_type = "_Self" }, ctx, out);
    }
    for (interface.constants) |constant| {
        try translateConstant(constant, out);
    }
    try out.print("};\n\n", .{});

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
    try out.print("pub usingnamespace Methods(_Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime _Self: type) type {\n", .{interface.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = _Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct{\n", .{});
    for (interface.methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = "_Self" }, ctx, out);
    }
    for (interface.signals) |signal| {
        try translateSignal(allocator, signal, ctx, out);
    }
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LMethods(comptime _Self: type) type {\n", .{interface.name});
    try out.print("return struct {\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(_Self);\n", .{interface.name});
    // See the note above on this implicit prerequisite
    if (interface.prerequisites.len == 0) {
        try out.print("pub usingnamespace gobject.Object.Methods(_Self);\n", .{});
    }
    for (interface.prerequisites) |prerequisite| {
        try out.print("pub usingnamespace ", .{});
        try translateName(allocator, prerequisite.name, out);
        try out.print(".Methods(_Self);\n", .{});
    }
    try out.print("pub usingnamespace $LExtraMethods(_Self);\n", .{interface.name});
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime _Self: type) type {\n", .{interface.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(_Self) else struct {};\n", .{ interface.name, interface.name });
    try out.print("}\n\n", .{});

    // virtual methods mixins
    if (interface.type_struct) |type_struct| {
        try out.print("fn $LOwnVirtualMethods(comptime _Iface: type, comptime _Instance: type) type {\n", .{interface.name});
        try out.print(
            \\const _i_dont_care_if_Iface_is_unused = _Iface;
            \\_ = _i_dont_care_if_Iface_is_unused;
            \\const _i_dont_care_if_Instance_is_unused = _Instance;
            \\_ = _i_dont_care_if_Instance_is_unused;
            \\
        , .{});
        try out.print("return struct{\n", .{});
        for (interface.virtual_methods) |virtual_method| {
            try translateVirtualMethod(allocator, virtual_method, "_Iface", type_struct, interface.name, ctx, out);
        }
        try out.print("};\n", .{});
        try out.print("}\n\n", .{});

        try out.print("fn $LVirtualMethods(comptime _Iface: type, comptime _Instance: type) type {\n", .{interface.name});
        try out.print("return struct{\n", .{});
        try out.print("pub usingnamespace $LOwnVirtualMethods(_Iface, _Instance);\n", .{interface.name});
        try out.print("pub usingnamespace $LExtraVirtualMethods(_Iface, _Instance);\n", .{interface.name});
        try out.print("};\n", .{});
        try out.print("}\n\n", .{});

        try out.print("fn $LExtraVirtualMethods(comptime _Iface: type, comptime _Instance: type) type {\n", .{interface.name});
        try out.print("return if (@hasDecl(extras, \"$LVirtualMethods\")) extras.$LVirtualMethods(_Iface, _Instance) else struct {};\n", .{ interface.name, interface.name });
        try out.print("}\n\n", .{});
    }
}

fn translateRecord(allocator: Allocator, record: gir.Record, ctx: TranslationContext, out: anytype) !void {
    // record type
    try translateDocumentation(record.documentation, out);
    try out.print("pub const $I = ", .{escapeTypeName(record.name)});
    if (record.isPointer()) {
        try out.print("*", .{});
    }
    if (record.isOpaque()) {
        try out.print("opaque {\n", .{});
    } else {
        try out.print("extern struct {\n", .{});
    }

    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print("pub const Instance = ", .{});
        try translateName(allocator, is_gtype_struct_for, out);
        try out.print(";\n", .{});
    }
    try out.print("const _Self = @This();\n\n", .{});

    if (!record.isOpaque()) {
        try translateLayoutElements(allocator, record.layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct{\n", .{});
    if (record.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
        }
    }
    for (record.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (record.constructors) |constructor| {
        try translateConstructor(allocator, constructor, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{record.name});
    try out.print("pub const Methods = $LMethods;\n", .{record.name});
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ record.name, record.name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{record.name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(_Self);\n", .{});
    if (record.is_gtype_struct_for != null) {
        try out.print("pub usingnamespace Instance.VirtualMethods(_Self, Instance);\n", .{});
    }
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime _Self: type) type {\n", .{record.name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = _Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct{\n", .{});
    for (record.methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LMethods(comptime _Self: type) type {\n", .{record.name});
    try out.print("return struct{\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(_Self);\n", .{record.name});
    if (record.is_gtype_struct_for) |is_gtype_struct_for| {
        try out.print("const Instance =", .{});
        try translateName(allocator, is_gtype_struct_for, out);
        try out.print(";\n", .{});
        try out.print(
            \\pub usingnamespace if (@hasDecl(Instance, "Parent") and @hasDecl(Instance.Parent, "Class"))
            \\    Instance.Parent.Class.Methods(_Self)
            \\else if (@hasDecl(Instance, "Parent"))
            \\    gobject.TypeClass.Methods(_Self)
            \\else
            \\    struct{}
            \\;
            \\
        , .{});
    }
    try out.print("pub usingnamespace $LExtraMethods(_Self);\n", .{record.name});
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime _Self: type) type {\n", .{record.name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(_Self) else struct {};\n", .{ record.name, record.name });
    try out.print("}\n\n", .{});
}

fn translateUnion(allocator: Allocator, @"union": gir.Union, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(@"union".documentation, out);
    try out.print("pub const $I = ", .{escapeTypeName(@"union".name)});
    if (@"union".isOpaque()) {
        try out.print("opaque {\n", .{});
    } else {
        try out.print("extern union {\n", .{});
    }
    try out.print("const _Self = @This();\n\n", .{});

    if (!@"union".isOpaque()) {
        try translateLayoutElements(allocator, @"union".layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    try out.print("pub const Own = struct{\n", .{});
    if (@"union".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
        }
    }
    for (@"union".functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    for (@"union".constructors) |constructor| {
        try translateConstructor(allocator, constructor, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const OwnMethods = $LOwnMethods;\n", .{@"union".name});
    try out.print("pub const Methods = $LMethods;\n", .{@"union".name});
    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n", .{ @"union".name, @"union".name });
    try out.print("pub const ExtraMethods = $LExtraMethods;\n\n", .{@"union".name});

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Methods(_Self);\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});

    // methods mixins
    try out.print("fn $LOwnMethods(comptime _Self: type) type {\n", .{@"union".name});
    try out.print(
        \\const _i_dont_care_if_Self_is_unused = _Self;
        \\_ = _i_dont_care_if_Self_is_unused;
        \\
    , .{});
    try out.print("return struct{\n", .{});
    for (@"union".methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LMethods(comptime _Self: type) type {\n", .{@"union".name});
    try out.print("return struct{\n", .{});
    try out.print("pub usingnamespace $LOwnMethods(_Self);\n", .{@"union".name});
    try out.print("pub usingnamespace $LExtraMethods(_Self);\n", .{@"union".name});
    try out.print("};\n", .{});
    try out.print("}\n\n", .{});

    try out.print("fn $LExtraMethods(comptime _Self: type) type {\n", .{@"union".name});
    try out.print("return if (@hasDecl(extras, \"$LMethods\")) extras.$LMethods(_Self) else struct {};\n", .{ @"union".name, @"union".name });
    try out.print("}\n\n", .{});
}

fn translateLayoutElements(allocator: Allocator, layout_elements: []const gir.LayoutElement, ctx: TranslationContext, out: anytype) !void {
    // This handling of bit fields makes no attempt to be general, so it can
    // avoid a lot of complexity present for bit fields in general. It only
    // handles bit fields backed by guint, and it assumes guint is 32 bits.
    var bit_field_offset: usize = 0;
    var n_bit_fields: usize = 0;
    var n_anon_fields: usize = 0;
    for (layout_elements) |layout_element| {
        if (layout_element == .field and layout_element.field.bits != null) {
            const field = layout_element.field;
            const bits = field.bits.?;
            if (field.type == .simple and field.type.simple.name != null and mem.eql(u8, field.type.simple.name.?.local, "guint")) {
                if (bit_field_offset == 0) {
                    try out.print("bitfields$L: packed struct(c_uint) {\n", .{n_bit_fields});
                }
                try translateDocumentation(field.documentation, out);
                try out.print("$I: u$L,\n", .{ field.name, bits });
                bit_field_offset += bits;
                // This implementation does not handle bit fields with members
                // crossing storage boundaries, since this does not appear in
                // any GIR I'm aware of. Such occurrences will result in invalid
                // Zig code.
                if (bit_field_offset >= 32) {
                    try out.print("},\n", .{});
                    bit_field_offset = 0;
                    n_bit_fields += 1;
                }
            } else {
                try translateDocumentation(field.documentation, out);
                try out.print("$I: @compileError(\"can't translate bitfields unless backed by guint\"),\n", .{field.name});
            }
        } else {
            if (bit_field_offset > 0) {
                // Pad out to 32 bits
                try out.print("_: u$L,\n", .{32 - bit_field_offset});
                try out.print("},\n", .{});
                bit_field_offset = 0;
                n_bit_fields += 1;
            }
            switch (layout_element) {
                .field => |field| {
                    try translateDocumentation(field.documentation, out);
                    try out.print("$I: ", .{field.name});
                    try translateFieldType(allocator, field.type, ctx, out);
                    try out.print(",\n", .{});
                },
                .record => |record| {
                    try out.print("anon$L: extern struct {\n", .{n_anon_fields});
                    try translateLayoutElements(allocator, record.layout_elements, ctx, out);
                    try out.print("},\n", .{});
                    n_anon_fields += 1;
                },
                .@"union" => |@"union"| {
                    try out.print("anon$L: extern union {\n", .{n_anon_fields});
                    try translateLayoutElements(allocator, @"union".layout_elements, ctx, out);
                    try out.print("},\n", .{});
                    n_anon_fields += 1;
                },
            }
        }
    }
    // Handle trailing bit fields
    if (bit_field_offset > 0) {
        try out.print("_: u$L,\n", .{32 - bit_field_offset});
        try out.print("},\n", .{});
    }
}

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, ctx: TranslationContext, out: anytype) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = typeIsPointer(simple_type, false, ctx),
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = arrayTypeIsPointer(array_type, false, ctx),
        }, ctx, out),
        .callback => |callback| try translateCallback(allocator, callback, .{
            .nullable = true,
        }, ctx, out),
    }
}

fn translateBitField(allocator: Allocator, bit_field: gir.BitField, ctx: TranslationContext, out: anytype) !void {
    var members = [1]?gir.Member{null} ** 64;
    var needs_u64 = false;
    for (bit_field.members) |member| {
        if (member.value > 0) {
            if (member.value > math.maxInt(u32)) {
                needs_u64 = true;
            }
            const as_u64: u64 = @intCast(member.value);
            const pos = math.log2_int(u64, as_u64);
            // There are several bit fields who have members declared that are
            // not powers of 2. Those (and all other members) will be translated
            // as constants.
            if (math.pow(u64, 2, pos) == as_u64) {
                // For duplicate field names, only the first name is used
                if (members[pos] == null) {
                    members[pos] = member;
                }
            }
        }
    }
    const backing_int = if (needs_u64) "u64" else "c_uint";

    try translateDocumentation(bit_field.documentation, out);
    try out.print("pub const $I = packed struct($L) {\n", .{ escapeTypeName(bit_field.name), backing_int });
    for (members, 0..) |maybe_member, i| {
        if (maybe_member) |member| {
            try out.print("$I: bool = false,\n", .{member.name});
        } else if (needs_u64 or i < 32) {
            try out.print("_padding$L: bool = false,\n", .{i});
        }
    }

    try out.print("\nconst _Self = @This();\n", .{});
    // Adding all values as constants makes sure we don't miss anything that was
    // 0, not a power of 2, etc. It may be somewhat confusing to have the
    // members we just translated as fields also included here, but this is
    // actually useful for some weird bit field types which are not entirely bit
    // fields anyways. As an example of this, see DebugColorFlags in Gst-1.0. We
    // also need to keep track of duplicate members, since GstVideo-1.0 has
    // multiple members with the same name :thinking:
    // https://gitlab.gnome.org/GNOME/gobject-introspection/-/issues/264
    var seen = StringHashMapUnmanaged(void){};
    defer seen.deinit(allocator);
    for (bit_field.members) |member| {
        if (!seen.contains(member.name)) {
            try out.print("const $I: _Self = @bitCast(@as($L, $L));\n", .{ member.name, backing_int, member.value });
        }
        try seen.put(allocator, member.name, {});
    }

    try out.print("\npub const Own = struct{\n", .{});
    if (bit_field.getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
        }
    }
    for (bit_field.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n\n", .{ bit_field.name, bit_field.name });

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});
}

fn translateEnum(allocator: Allocator, @"enum": gir.Enum, ctx: TranslationContext, out: anytype) !void {
    try translateDocumentation(@"enum".documentation, out);
    try out.print("pub const $I = enum(c_int) {\n", .{escapeTypeName(@"enum".name)});

    // Zig does not allow enums to have multiple fields with the same value, so
    // we must translate any duplicate values as constants referencing the
    // "base" value
    var seen_values = AutoHashMapUnmanaged(i65, gir.Member){};
    defer seen_values.deinit(allocator);
    var duplicate_members = ArrayListUnmanaged(gir.Member){};
    defer duplicate_members.deinit(allocator);
    for (@"enum".members) |member| {
        if (seen_values.get(member.value) == null) {
            try out.print("$I = $L,\n", .{ member.name, member.value });
            try seen_values.put(allocator, member.value, member);
        } else {
            try duplicate_members.append(allocator, member);
        }
    }

    try out.print("\nconst _Self = @This();\n\n", .{});

    for (duplicate_members.items) |member| {
        try out.print("pub const $I = _Self.$I;\n", .{ member.name, seen_values.get(member.value).?.name });
    }

    try out.print("pub const Own = struct{\n", .{});
    if (@"enum".getTypeFunction()) |get_type_function| {
        if (mem.endsWith(u8, get_type_function.c_identifier, "get_type")) {
            try translateFunction(allocator, get_type_function, .{ .self_type = "_Self" }, ctx, out);
        }
    }
    for (@"enum".functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = "_Self" }, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const Extras = if (@hasDecl(extras, $S)) extras.$I else struct {};\n\n", .{ @"enum".name, @"enum".name });

    try out.print("pub usingnamespace Own;\n", .{});
    try out.print("pub usingnamespace Extras;\n", .{});

    try out.print("};\n\n", .{});
}

const TranslateFunctionOptions = struct {
    self_type: ?[]const u8 = null,
};

fn isFunctionTranslatable(function: gir.Function) bool {
    return function.moved_to == null;
}

fn translateFunction(allocator: Allocator, function: gir.Function, options: TranslateFunctionOptions, ctx: TranslationContext, out: anytype) !void {
    if (!isFunctionTranslatable(function)) {
        return;
    }

    const fnName = try toCamelCase(allocator, function.name, "_");
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
    try translateParameters(allocator, function.parameters, .{
        .self_type = options.self_type,
        .throws = function.throws,
    }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, function.return_value, .{
        .force_nullable = function.throws and anyTypeIsPointer(function.return_value.type, false, ctx),
    }, ctx, out);
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

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, options: TranslateFunctionOptions, ctx: TranslationContext, out: anytype) !void {
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
        // TODO: doesn't respect the self_type option, even though nobody cares right now
        .return_value = .{ .type = .{ .simple = .{
            .name = .{ .ns = null, .local = "_Self" },
            .c_type = "_Self*",
        } } },
        .throws = constructor.throws,
        .documentation = constructor.documentation,
    }, options, ctx, out);
}

fn isMethodTranslatable(method: gir.Method) bool {
    return method.moved_to == null;
}

fn translateMethod(allocator: Allocator, method: gir.Method, options: TranslateFunctionOptions, ctx: TranslationContext, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = method.name,
        .c_identifier = method.c_identifier,
        .moved_to = method.moved_to,
        .parameters = method.parameters,
        .return_value = method.return_value,
        .throws = method.throws,
        .documentation = method.documentation,
    }, options, ctx, out);
}

fn translateVirtualMethod(allocator: Allocator, virtual_method: gir.VirtualMethod, container_name: []const u8, container_type: gir.Name, instance_type: []const u8, ctx: TranslationContext, out: anytype) !void {
    var upper_method_name = try toCamelCase(allocator, virtual_method.name, "_");
    defer allocator.free(upper_method_name);
    if (upper_method_name.len > 0) {
        upper_method_name[0] = ascii.toUpper(upper_method_name[0]);
    }

    // implementation
    try translateDocumentation(virtual_method.documentation, out);
    try out.print("pub fn implement$L(p_class: *$I, p_implementation: ", .{ upper_method_name, container_name });
    try translateVirtualMethodImplementationType(allocator, virtual_method, "_Instance", ctx, out);
    try out.print(") void {\n", .{});
    try out.print("@as(*", .{});
    try translateName(allocator, container_type, out);
    try out.print(", @ptrCast(@alignCast(p_class))).$I = @ptrCast(p_implementation);\n", .{virtual_method.name});
    try out.print("}\n\n", .{});

    // call
    try out.print("pub fn call$L(p_class: *$I, ", .{ upper_method_name, container_name });
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{
        .force_nullable = virtual_method.throws and anyTypeIsPointer(virtual_method.return_value.type, false, ctx),
    }, ctx, out);
    try out.print(" {\n", .{});
    try out.print("return @as(*", .{});
    try translateName(allocator, container_type, out);
    try out.print(", @ptrCast(@alignCast(p_class))).$I.?(", .{virtual_method.name});
    try translateParameterNames(allocator, virtual_method.parameters, .{ .throws = virtual_method.throws }, out);
    try out.print(");\n", .{});
    try out.print("}\n\n", .{});
}

fn translateVirtualMethodImplementationType(allocator: Allocator, virtual_method: gir.VirtualMethod, instance_type: []const u8, ctx: TranslationContext, out: anytype) !void {
    try out.print("*const fn (", .{});
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") callconv(.C) ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{
        .force_nullable = virtual_method.throws and anyTypeIsPointer(virtual_method.return_value.type, false, ctx),
    }, ctx, out);
}

fn translateSignal(allocator: Allocator, signal: gir.Signal, ctx: TranslationContext, out: anytype) !void {
    var upper_signal_name = try toCamelCase(allocator, signal.name, "-");
    defer allocator.free(upper_signal_name);
    if (upper_signal_name.len > 0) {
        upper_signal_name[0] = ascii.toUpper(upper_signal_name[0]);
    }

    // normal connection
    try translateDocumentation(signal.documentation, out);
    try out.print("pub fn connect$L(p_self: *_Self, comptime P_T: type, p_callback: ", .{upper_signal_name});
    // TODO: verify that P_T is a pointer type or compatible
    try translateSignalCallbackType(allocator, signal, ctx, out);
    try out.print(", p_data: P_T, p_options: struct { after: bool = false }) c_ulong {\n", .{});
    try out.print("return gobject.signalConnectData(p_self.as(gobject.Object), $S, @ptrCast(p_callback), p_data, null, .{ .after = p_options.after });\n", .{signal.name});
    try out.print("}\n\n", .{});
}

fn translateSignalCallbackType(allocator: Allocator, signal: gir.Signal, ctx: TranslationContext, out: anytype) !void {
    try out.print("*const fn (*_Self", .{});
    if (signal.parameters.len > 0) {
        try out.print(", ", .{});
    }
    try translateParameters(allocator, signal.parameters, .{
        .self_type = "_Self",
        .gobject_context = true,
    }, ctx, out);
    try out.print(", P_T) callconv(.C) ", .{});
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
    .{ "gboolean", "c_int" },
    .{ "bool", "bool" },
    .{ "_Bool", "bool" },
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
    .{ "gintptr", "isize" },
    .{ "guintptr", "usize" },
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

fn typeIsPointer(@"type": gir.Type, gobject_context: bool, ctx: TranslationContext) bool {
    const name = @"type".name orelse {
        const c_type = @"type".c_type orelse return false;
        return parseCPointerType(c_type) != null;
    };
    if (ctx.isPointerType(name)) {
        return true;
    }
    const c_type = @"type".c_type orelse {
        if (builtins.get(name.local)) |builtin| {
            return zigTypeIsPointer(builtin);
        }
        return gobject_context and ctx.isObjectType(name);
    };
    if (builtins.get(c_type)) |builtin| {
        return zigTypeIsPointer(builtin);
    }
    if (parseCPointerType(c_type) != null) {
        return true;
    }
    if (builtins.get(name.local)) |builtin| {
        return zigTypeIsPointer(builtin);
    }
    return gobject_context and ctx.isObjectType(name);
}

fn translateType(allocator: Allocator, @"type": gir.Type, options: TranslateTypeOptions, ctx: TranslationContext, out: anytype) CreateBindingsError!void {
    if (options.nullable) {
        try out.print("?", .{});
    }
    const name = @"type".name orelse {
        const c_type = @"type".c_type orelse {
            try out.print("@compileError(\"no type information available\")", .{});
            return;
        };
        // Last-ditch attempt to salvage some code generation by translating pointers as opaque
        if (parseCPointerType(c_type)) |pointer| {
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

    // The none builtin needs to be handled very early, because otherwise it
    // might be confused with the use of void as an opaque type.
    if (mem.eql(u8, name.local, "none")) {
        try out.print("void", .{});
        return;
    }

    var c_type = @"type".c_type orelse {
        // We should check for builtins first; utf8 is a common type to end up with here
        if (builtins.get(name.local)) |builtin| {
            try out.print("$L", .{builtin});
            return;
        }

        // At this point, the only thing we can do is assume a plain type. GIR
        // is extremely annoying when it comes to precisely representing types
        // in certain contexts, such as signals and properties (basically
        // anything that doesn't have a direct C equivalent). The context is
        // needed here to correctly guess whether the type should be a pointer
        // or not.
        if (options.gobject_context and ctx.isObjectType(name)) {
            try out.print("*", .{});
        }
        try translateName(allocator, name, out);
        return;
    };
    // Special cases that we have to handle early or they will be misinterpreted
    // as non-pointers
    if (mem.eql(u8, c_type, "gpointer")) {
        c_type = "void*";
        // Wow, a special case of a special case :O
        if (mem.eql(u8, name.local, "utf8") or mem.eql(u8, name.local, "filename")) {
            try out.print("[*:0]u8", .{});
            return;
        }
    } else if (mem.eql(u8, c_type, "gconstpointer")) {
        c_type = "const void*";
        if (mem.eql(u8, name.local, "utf8") or mem.eql(u8, name.local, "filename")) {
            try out.print("[*:0]const u8", .{});
            return;
        }
    }

    // The gpointer and gconstpointer builtins need to be handled before we get
    // too far, or the conversion of c_type gpointer and gconstpointer to void*
    // and const void* above will cause a confusing extra level of pointer in
    // the output.
    if (mem.eql(u8, name.local, "gpointer")) {
        // GIR represents the gconstpointer type with a name of "gpointer" and a
        // c_type of "gconstpointer", because fuck you, I guess
        if (mem.eql(u8, c_type, "const void*")) {
            try out.print("*const anyopaque", .{});
        } else {
            try out.print("*anyopaque", .{});
        }
        return;
    }

    // The c_type is more reliable than name when looking for builtins, since
    // the name often does not include any information about whether the type is
    // a pointer
    if (builtins.get(c_type)) |builtin| {
        try out.print("$L", .{builtin});
        return;
    }

    if (parseCPointerType(c_type)) |pointer| {
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
    if (builtins.get(name.local)) |builtin| {
        try out.print("$L", .{builtin});
        return;
    }

    // If we've gotten this far, we must have a plain type. The same caveats as
    // explained in the no c_type case apply here, with respect to "GObject
    // context".
    if (options.gobject_context and ctx.isObjectType(name)) {
        try out.print("*", .{});
    }
    try translateName(allocator, name, out);
}

test "translateType" {
    try testTranslateType("c_int", .{ .name = .{ .ns = null, .local = "gboolean" }, .c_type = "gboolean" }, .{});
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
    try testTranslateType("*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true, .class_names = &.{"Gdk.Event"} });
    try testTranslateType("?*gdk.Event", .{ .name = .{ .ns = "Gdk", .local = "Event" } }, .{ .gobject_context = true, .nullable = true, .class_names = &.{"Gdk.Event"} });
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
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gpointer" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gpointer" }, .{ .nullable = true });
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gconstpointer" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "gconstpointer" }, .{ .nullable = true });
    try testTranslateType("[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gpointer" }, .{});
    try testTranslateType("?[*:0]u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gpointer" }, .{ .nullable = true });
    try testTranslateType("[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gconstpointer" }, .{});
    try testTranslateType("?[*:0]const u8", .{ .name = .{ .ns = null, .local = "filename" }, .c_type = "gconstpointer" }, .{ .nullable = true });
    // Callback types behave as disguised pointer types
    try testTranslateType("gobject.InstanceInitFunc", .{ .name = .{ .ns = "GObject", .local = "InstanceInitFunc" }, .c_type = "GInstanceInitFunc" }, .{ .is_pointer = true, .callback_names = &.{"GObject.InstanceInitFunc"} });
    try testTranslateType("?gobject.InstanceInitFunc", .{ .name = .{ .ns = "GObject", .local = "InstanceInitFunc" }, .c_type = "GInstanceInitFunc" }, .{ .nullable = true, .is_pointer = true, .callback_names = &.{"GObject.InstanceInitFunc"} });
    // TODO: why is this not an array type in GIR? This inhibits a good translation here.
    // See the invalidated_properties parameter in Gio and similar.
    try testTranslateType("*const [*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar* const*" }, .{});
    try testTranslateType("?*const [*:0]const u8", .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "const gchar* const*" }, .{ .nullable = true });
    // The C code is written using gpointer as the c_type presumably to make it
    // easier to write these as generic callbacks
    try testTranslateType("*gobject.Object", .{ .name = .{ .ns = "GObject", .local = "Object" }, .c_type = "gpointer" }, .{});
    try testTranslateType("?*gobject.Object", .{ .name = .{ .ns = "GObject", .local = "Object" }, .c_type = "gpointer" }, .{ .nullable = true });
    try testTranslateType("*const glib.Bytes", .{ .name = .{ .ns = "GLib", .local = "Bytes" }, .c_type = "gconstpointer" }, .{});
    try testTranslateType("?*const glib.Bytes", .{ .name = .{ .ns = "GLib", .local = "Bytes" }, .c_type = "gconstpointer" }, .{ .nullable = true });
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
    // Not ideal, but also not possible to do much better
    try testTranslateType("*anyopaque", .{ .c_type = "_GtkMountOperationHandler*" }, .{});
    try testTranslateType("*const anyopaque", .{ .c_type = "const _GtkMountOperationHandler*" }, .{});
    try testTranslateType("?*anyopaque", .{ .c_type = "_GtkMountOperationHandler*" }, .{ .nullable = true });
    try testTranslateType("?*const anyopaque", .{ .c_type = "const _GtkMountOperationHandler*" }, .{ .nullable = true });
}

const TestTranslateTypeOptions = struct {
    nullable: bool = false,
    gobject_context: bool = false,
    is_pointer: ?bool = null,
    class_names: []const []const u8 = &.{},
    callback_names: []const []const u8 = &.{},

    fn initTranslationContext(self: TestTranslateTypeOptions, base_allocator: Allocator) !TranslationContext {
        var ctx = TranslationContext.init(base_allocator);
        const allocator = ctx.arena.allocator();
        for (self.class_names) |class_name| {
            const ns_sep = mem.indexOfScalar(u8, class_name, '.').?;
            const ns_name = class_name[0..ns_sep];
            const local_name = class_name[ns_sep + 1 ..];
            const ns_map = try ctx.namespaces.getOrPut(allocator, ns_name);
            if (!ns_map.found_existing) {
                ns_map.value_ptr.* = .{
                    .name = ns_name,
                    .version = "0",
                    .aliases = .{},
                    .classes = .{},
                    .interfaces = .{},
                    .records = .{},
                    .unions = .{},
                    .bit_fields = .{},
                    .enums = .{},
                    .functions = .{},
                    .callbacks = .{},
                    .constants = .{},
                };
            }
            try ns_map.value_ptr.classes.put(allocator, local_name, .{
                .name = local_name,
                .layout_elements = undefined,
                .get_type = undefined,
            });
        }
        for (self.callback_names) |callback_name| {
            const ns_sep = mem.indexOfScalar(u8, callback_name, '.').?;
            const ns_name = callback_name[0..ns_sep];
            const local_name = callback_name[ns_sep + 1 ..];
            const ns_map = try ctx.namespaces.getOrPut(allocator, ns_name);
            if (!ns_map.found_existing) {
                ns_map.value_ptr.* = .{
                    .name = ns_name,
                    .version = "0",
                    .aliases = .{},
                    .classes = .{},
                    .interfaces = .{},
                    .records = .{},
                    .unions = .{},
                    .bit_fields = .{},
                    .enums = .{},
                    .functions = .{},
                    .callbacks = .{},
                    .constants = .{},
                };
            }
            try ns_map.value_ptr.callbacks.put(allocator, local_name, .{
                .name = local_name,
                .parameters = undefined,
                .return_value = undefined,
            });
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

    try testing.expectEqual(options.is_pointer orelse zigTypeIsPointer(expected), typeIsPointer(@"type", options.gobject_context, ctx));
}

fn arrayTypeIsPointer(@"type": gir.ArrayType, gobject_context: bool, ctx: TranslationContext) bool {
    if (@"type".name != null and @"type".c_type != null) {
        return typeIsPointer(.{ .name = @"type".name, .c_type = @"type".c_type }, gobject_context, ctx);
    }
    if (@"type".fixed_size == null) {
        return true;
    }
    if (@"type".c_type) |c_type| {
        return std.mem.eql(u8, c_type, "gpointer") or
            std.mem.eql(u8, c_type, "gconstpointer") or
            std.mem.eql(u8, c_type, "GStrv") or
            parseCPointerType(c_type) != null;
    }
    return false;
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
                .nullable = @"type".zero_terminated and typeIsPointer(element, options.gobject_context, ctx),
            }, ctx, out);
        },
        .array => |element| {
            var modified_element = element;
            modified_element.c_type = element_c_type orelse element.c_type;
            try translateArrayType(allocator, modified_element, .{
                .gobject_context = options.gobject_context,
                .nullable = @"type".zero_terminated and arrayTypeIsPointer(element, options.gobject_context, ctx),
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
    }, .{ .gobject_context = true, .class_names = &.{"Gio.File"} });
}

fn testTranslateArrayType(expected: []const u8, @"type": gir.ArrayType, options: TestTranslateTypeOptions) !void {
    var ctx = try options.initTranslationContext(testing.allocator);
    defer ctx.deinit();

    var buf = ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    var out = zigWriter(buf.writer());
    try translateArrayType(testing.allocator, @"type", options.options(), ctx, &out);
    try testing.expectEqualStrings(expected, buf.items);

    try testing.expectEqual(options.is_pointer orelse zigTypeIsPointer(expected), arrayTypeIsPointer(@"type", options.gobject_context, ctx));
}

fn anyTypeIsPointer(@"type": gir.AnyType, gobject_context: bool, ctx: TranslationContext) bool {
    return switch (@"type") {
        .simple => |simple_type| typeIsPointer(simple_type, gobject_context, ctx),
        .array => |array_type| arrayTypeIsPointer(array_type, gobject_context, ctx),
    };
}

fn zigTypeIsPointer(expected: []const u8) bool {
    return mem.startsWith(u8, expected, "*") or
        mem.startsWith(u8, expected, "?*") or
        mem.startsWith(u8, expected, "[*") or
        mem.startsWith(u8, expected, "?[*");
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

const TranslateCallbackOptions = struct {
    named: bool = false,
    nullable: bool = false,
};

fn translateCallback(allocator: Allocator, callback: gir.Callback, options: TranslateCallbackOptions, ctx: TranslationContext, out: anytype) !void {
    // TODO: hard-coded workarounds until https://github.com/ziglang/zig/issues/12325 is fixed
    if (options.named) {
        if (mem.eql(u8, callback.name, "ClosureNotify")) {
            try out.print("pub const ClosureNotify = *const fn (p_data: ?*anyopaque, p_closure: *anyopaque) callconv(.C) void;\n\n", .{});
            return;
        } else if (mem.eql(u8, callback.name, "MemoryCopyFunction")) {
            try out.print("pub const MemoryCopyFunction = *const fn (p_mem: ?*anyopaque, p_offset: isize, p_size: isize) callconv(.C) *anyopaque;\n\n", .{});
            return;
        }
    }

    if (options.named) {
        try translateDocumentation(callback.documentation, out);
        try out.print("pub const $I = ", .{escapeTypeName(callback.name)});
    }

    if (options.nullable) {
        try out.print("?", .{});
    }
    try out.print("*const fn (", .{});
    try translateParameters(allocator, callback.parameters, .{ .throws = callback.throws }, ctx, out);
    try out.print(") callconv(.C) ", .{});
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = (callback.return_value.nullable or callback.throws) and typeIsPointer(simple_type, false, ctx),
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = (callback.return_value.nullable or callback.throws) and arrayTypeIsPointer(array_type, false, ctx),
        }, ctx, out),
    }

    if (options.named) {
        try out.print(";\n\n", .{});
    }
}

const TranslateParametersOptions = struct {
    self_type: ?[]const u8 = null,
    gobject_context: bool = false,
    throws: bool = false,
};

fn translateParameters(allocator: Allocator, parameters: []const gir.Parameter, options: TranslateParametersOptions, ctx: TranslationContext, out: anytype) !void {
    // GIR does not appear to consider the instance-parameter when numbering
    // parameters for closure metadata
    const param_offset: usize = if (parameters.len > 0 and parameters[0].instance) 1 else 0;
    var force_nullable = AutoHashMapUnmanaged(usize, void){};
    defer force_nullable.deinit(allocator);
    for (parameters) |parameter| {
        // TODO: GIR is pretty bad about using these attributes correctly, so we might want some extra checks
        // See https://gitlab.gnome.org/GNOME/gobject-introspection/-/issues/285
        if (parameter.closure) |closure| {
            const idx = closure + param_offset;
            if (idx < parameters.len and parameterTypeIsPointer(parameters[idx].type, options.gobject_context, ctx)) {
                try force_nullable.put(allocator, closure + param_offset, {});
            }
        }
        if (parameter.destroy) |destroy| {
            const idx = destroy + param_offset;
            if (idx < parameters.len and parameterTypeIsPointer(parameters[idx].type, options.gobject_context, ctx)) {
                try force_nullable.put(allocator, destroy + param_offset, {});
            }
        }
    }

    for (parameters, 0..) |parameter, i| {
        try translateParameter(allocator, parameter, .{
            .self_type = options.self_type,
            .force_nullable = force_nullable.get(i) != null,
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
    self_type: ?[]const u8 = null,
    force_nullable: bool = false,
    gobject_context: bool = false,
};

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, options: TranslateParameterOptions, ctx: TranslationContext, out: anytype) !void {
    if (parameter.type == .varargs) {
        try out.print("...", .{});
        return;
    }

    try translateParameterName(allocator, parameter.name, out);
    try out.print(": ", .{});
    switch (parameter.type) {
        .simple => |simple_type| {
            // This is kind of a hacky way of ensuring the self type is used
            // if applicable. We cannot always be sure that an
            // instance-parameter will even only occur in the context of a
            // container (thanks, Gee-0.8), and this helps unify the pointer
            // handling logic.
            const effective_type = if (parameter.instance and options.self_type != null) gir.Type{
                .name = .{ .ns = null, .local = options.self_type.? },
                .c_type = simple_type.c_type,
            } else simple_type;
            try translateType(allocator, effective_type, .{
                .nullable = options.force_nullable or parameter.isNullable(),
                .gobject_context = options.gobject_context,
            }, ctx, out);
        },
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = options.force_nullable or parameter.isNullable(),
            .gobject_context = options.gobject_context,
        }, ctx, out),
        .varargs => unreachable, // handled above
    }
}

fn parameterTypeIsPointer(@"type": gir.ParameterType, gobject_context: bool, ctx: TranslationContext) bool {
    return switch (@"type") {
        .simple => |simple_type| typeIsPointer(simple_type, gobject_context, ctx),
        .array => |array_type| arrayTypeIsPointer(array_type, gobject_context, ctx),
        .varargs => false,
    };
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
    const translated_name = try fmt.allocPrint(allocator, "p_{s}", .{parameter_name});
    defer allocator.free(translated_name);
    try out.print("$I", .{translated_name});
}

const TranslateReturnValueOptions = struct {
    /// Whether the return value should be forced to be nullable. This is
    /// relevant for "throwing" functions, where return values are expected to
    /// be null in case of failure, but for some reason GIR doesn't mark them as
    /// nullable explicitly.
    force_nullable: bool = false,
    gobject_context: bool = false,
};

fn translateReturnValue(allocator: Allocator, return_value: gir.ReturnValue, options: TranslateReturnValueOptions, ctx: TranslationContext, out: anytype) !void {
    switch (return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = options.force_nullable or return_value.isNullable(),
            .gobject_context = options.gobject_context,
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = options.force_nullable or return_value.isNullable(),
            .gobject_context = options.gobject_context,
        }, ctx, out),
    }
}

fn translateDocumentation(documentation: ?gir.Documentation, out: anytype) !void {
    if (documentation) |doc| {
        var lines = mem.split(u8, doc.text, "\n");
        while (lines.next()) |line| {
            try out.print("/// $L\n", .{line});
        }
    }
}

const type_name_escapes = ComptimeStringMap([]const u8, .{
    .{ "Class", "Class_" },
    .{ "Iface", "Iface_" },
    .{ "Parent", "Parent_" },
    .{ "Implements", "Implements_" },
    .{ "Own", "Own_" },
    .{ "OwnMethods", "OwnMethods_" },
    .{ "Methods", "Methods_" },
    .{ "OwnVirtualMethods", "OwnVirtualMethods_" },
    .{ "VirtualMethods", "VirtualMethods_" },
    .{ "ExtraVirtualMethods", "ExtraVirtualMethods_" },
    .{ "Extras", "Extras_" },
    .{ "ExtraMethods", "ExtraMethods_" },
});

/// Escapes a potentially problematic type name (such as Class) with an
/// alternative which will not collide with other names used in codegen.
fn escapeTypeName(name: []const u8) []const u8 {
    return type_name_escapes.get(name) orelse name;
}

fn translateName(allocator: Allocator, name: gir.Name, out: anytype) !void {
    try translateNameNs(allocator, name.ns, out);
    try out.print("$I", .{escapeTypeName(name.local)});
}

fn translateNameNs(allocator: Allocator, nameNs: ?[]const u8, out: anytype) !void {
    if (nameNs != null) {
        const type_ns = try ascii.allocLowerString(allocator, nameNs.?);
        defer allocator.free(type_ns);
        try out.print("$I.", .{type_ns});
    }
}

fn toCamelCase(allocator: Allocator, name: []const u8, word_sep: []const u8) ![]u8 {
    var out = ArrayListUnmanaged(u8){};
    try out.ensureTotalCapacity(allocator, name.len);
    var words = mem.split(u8, name, word_sep);
    var i: usize = 0;
    while (words.next()) |word| {
        if (word.len > 0) {
            if (i == 0) {
                out.appendSliceAssumeCapacity(word);
            } else {
                out.appendAssumeCapacity(ascii.toUpper(word[0]));
                out.appendSliceAssumeCapacity(word[1..]);
            }
            i += 1;
        } else if (i == 0) {
            out.appendSliceAssumeCapacity("_");
        }
    }
    return try out.toOwnedSlice(allocator);
}

test "toCamelCase" {
    try testToCamelCase("hello", "hello", "-");
    try testToCamelCase("hello", "hello", "_");
    try testToCamelCase("helloWorld", "hello_world", "_");
    try testToCamelCase("helloWorld", "hello-world", "-");
    try testToCamelCase("helloWorldManyWords", "hello-world-many-words", "-");
    try testToCamelCase("helloWorldManyWords", "hello_world_many_words", "_");
    try testToCamelCase("__hidden", "__hidden", "-");
    try testToCamelCase("__hidden", "__hidden", "_");
}

fn testToCamelCase(expected: []const u8, input: []const u8, word_sep: []const u8) !void {
    const actual = try toCamelCase(testing.allocator, input, word_sep);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(expected, actual);
}

pub const CreateBuildFileError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn createBuildFile(allocator: Allocator, repositories: []const gir.Repository, output_dir: fs.Dir) CreateBuildFileError!void {
    var repository_map = RepositoryMap{};
    defer repository_map.deinit(allocator);
    for (repositories) |repo| {
        try repository_map.put(allocator, .{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    var raw_source = ArrayListUnmanaged(u8){};
    defer raw_source.deinit(allocator);
    var out = zigWriter(raw_source.writer(allocator));

    try out.print("const std = @import(\"std\");\n\n", .{});

    try out.print("pub fn build(b: *std.Build) void {\n", .{});
    try out.print(
        \\const target = b.standardTargetOptions(.{});
        \\const optimize = b.standardOptimizeOption(.{});
        \\
    , .{});

    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        try out.print(
            \\const $I = b.addModule($S, .{
            \\    .root_source_file = .{ .path = b.pathJoin(&.{ "src", $S ++ ".zig" }) },
            \\    .target = target,
            \\    .optimize = optimize,
            \\});
            \\
        , .{ module_name, module_name, module_name });

        try out.print("$I.link_libc = true;\n", .{module_name});
        for (repo.packages) |package| {
            try out.print("$I.linkSystemLibrary($S, .{});\n", .{ module_name, package.name });
        }
    }

    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        var seen = RepositorySet{};
        defer seen.deinit(allocator);
        var needed_deps = ArrayListUnmanaged(gir.Include){};
        defer needed_deps.deinit(allocator);
        if (repository_map.get(.{ .name = repo.namespace.name, .version = repo.namespace.version })) |dep_repo| {
            try needed_deps.appendSlice(allocator, dep_repo.includes);
        }
        while (needed_deps.popOrNull()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                const dep_module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
                defer allocator.free(dep_module_name);
                try out.print("$I.addImport($S, $I);\n", .{ module_name, dep_module_name, dep_module_name });

                try seen.put(allocator, needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try needed_deps.appendSlice(allocator, dep_repo.includes);
                }
            }
        }

        // The self-dependency is useful for extras files to be able to import their own module by name
        try out.print("$I.addImport($S, $I);\n\n", .{ module_name, module_name, module_name });
    }

    try out.print("}\n", .{});

    try raw_source.append(allocator, 0);
    var ast = try zig.Ast.parse(allocator, raw_source.items[0 .. raw_source.items.len - 1 :0], .zig);
    defer ast.deinit(allocator);
    const fmt_source = try ast.render(allocator);
    defer allocator.free(fmt_source);
    try output_dir.writeFile("build.zig", fmt_source);
}

pub const CreateAbiTestsError = Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn createAbiTests(allocator: Allocator, repositories: []const gir.Repository, output_dir: fs.Dir) CreateAbiTestsError!void {
    for (repositories) |repo| {
        var output_file = output_file: {
            const name = try fmt.allocPrint(allocator, "{s}-{s}.abi.zig", .{ repo.namespace.name, repo.namespace.version });
            defer allocator.free(name);
            _ = ascii.lowerString(name, name);
            break :output_file try output_dir.createFile(name, .{});
        };
        defer output_file.close();
        var bw = io.bufferedWriter(output_file.writer());
        var out = zigWriter(bw.writer());

        const ns = repo.namespace;
        const pkg = try ascii.allocLowerString(allocator, ns.name);
        defer allocator.free(pkg);

        try out.print("const c = @cImport({\n", .{});
        for (repo.c_includes) |c_include| {
            try out.print("@cInclude($S);\n", .{c_include.name});
        }
        try out.print("});\n", .{});
        try out.print("const std = @import(\"std\");\n", .{});
        {
            const import_name = try moduleNameAlloc(allocator, ns.name, ns.version);
            defer allocator.free(import_name);
            try out.print("const $I = @import($S);\n\n", .{ pkg, import_name });
        }

        try out.print(
            \\fn checkCompatibility(comptime ExpectedType: type, comptime ActualType: type) !void {
            \\    // translate-c doesn't seem to want to translate va_list to std.builtin.VaList
            \\    if (ActualType == std.builtin.VaList) return;
            \\
            \\    const expected_type_info = @typeInfo(ExpectedType);
            \\    const actual_type_info = @typeInfo(ActualType);
            \\    switch (expected_type_info) {
            \\        .Void => switch (actual_type_info) {
            \\            .Void => {},
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        .Bool => switch (actual_type_info) {
            \\            .Bool => {},
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        .Float => |expected_float| switch (actual_type_info) {
            \\            .Float => |actual_float| try std.testing.expectEqual(expected_float.bits, actual_float.bits),
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        .Array => |expected_array| switch (actual_type_info) {
            \\            .Array => |actual_array| {
            \\                try std.testing.expectEqual(expected_array.len, actual_array.len);
            \\                try checkCompatibility(expected_array.child, actual_array.child);
            \\            },
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        .Struct => switch (actual_type_info) {
            \\            .Struct => {
            \\                try std.testing.expectEqual(@sizeOf(ExpectedType), @sizeOf(ActualType));
            \\                try std.testing.expectEqual(@alignOf(ExpectedType), @alignOf(ActualType));
            \\            },
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        .Union => switch (actual_type_info) {
            \\            .Union => {
            \\                try std.testing.expectEqual(@sizeOf(ExpectedType), @sizeOf(ActualType));
            \\                try std.testing.expectEqual(@alignOf(ExpectedType), @alignOf(ActualType));
            \\            },
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        // Opaque types show up more frequently in translate-c output due to its
            \\        // limitations. We'll just treat "opaque" as "I don't know" and accept any
            \\        // translation from zig-gobject.
            \\        .Opaque => {},
            \\        .Int => |expected_int| switch (actual_type_info) {
            \\            // Checking signedness here turns out to be too strict for many cases
            \\            // and does not affect actual ABI compatibility.
            \\            .Int => |actual_int| try std.testing.expectEqual(expected_int.bits, actual_int.bits),
            \\            .Enum => |actual_enum| try checkCompatibility(ExpectedType, actual_enum.tag_type),
            \\            .Struct => |actual_struct| {
            \\                try std.testing.expect(actual_struct.layout == .Packed);
            \\                try checkCompatibility(ExpectedType, actual_struct.backing_integer.?);
            \\            },
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
            \\                return error.TestUnexpectedType;
            \\            },
            \\        },
            \\        // Pointers are tricky to assert on, since we may translate some pointers
            \\        // differently from how they appear in C (e.g. *GtkWindow rather than *GtkWidget)
            \\        .Pointer => switch (actual_type_info) {
            \\            .Pointer => {},
            \\            .Optional => |actual_optional| try std.testing.expect(@typeInfo(actual_optional.child) == .Pointer),
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)}) ;
            \\                return error.TestUnexpectedType;
            \\            }
            \\        },
            \\        .Optional => |expected_optional| switch (@typeInfo(expected_optional.child)) {
            \\            .Pointer => try checkCompatibility(expected_optional.child, ActualType),
            \\            else => {
            \\                std.debug.print("unexpected C translated type: {s}\n", .{@typeName(ExpectedType)});
            \\                return error.TestUnexpectedType;
            \\            }
            \\        },
            \\        .Fn => |expected_fn| switch (actual_type_info) {
            \\            .Fn => |actual_fn| {
            \\                try std.testing.expectEqual(expected_fn.params.len, actual_fn.params.len);
            \\                try std.testing.expectEqual(expected_fn.calling_convention, actual_fn.calling_convention);
            \\                // The special casing of zero arguments here is because there are some
            \\                // headers (specifically in IBus) which do not properly use the (void)
            \\                // parameter list, so the function is translated as varargs even though
            \\                // it wasn't intended to be.
            \\                try std.testing.expect(expected_fn.is_var_args == actual_fn.is_var_args or (expected_fn.is_var_args and expected_fn.params.len == 0));
            \\                try std.testing.expect(expected_fn.return_type != null);
            \\                try std.testing.expect(actual_fn.return_type != null);
            \\                try checkCompatibility(expected_fn.return_type.?, actual_fn.return_type.?);
            \\                inline for (expected_fn.params, actual_fn.params) |expected_param, actual_param| {
            \\                    try std.testing.expect(expected_param.type != null);
            \\                    try std.testing.expect(actual_param.type != null);
            \\                    try checkCompatibility(expected_param.type.?, actual_param.type.?);
            \\                }
            \\            },
            \\            else => {
            \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)}) ;
            \\                return error.TestUnexpectedType;
            \\            }
            \\        },
            \\        else => {
            \\            std.debug.print("unexpected C translated type: {s}\n", .{@typeName(ExpectedType)});
            \\            return error.TestUnexpectedType;
            \\        },
            \\    }
            \\}
            \\
            \\
        , .{});

        for (ns.aliases) |alias| {
            const alias_name = escapeTypeName(alias.name);
            if (alias.c_type) |c_type| {
                try out.print("test $S {\n", .{alias_name});
                try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                try out.print(
                    \\const ExpectedType = c.$I;
                    \\const ActualType = $I.$I;
                    \\try checkCompatibility(ExpectedType, ActualType);
                    \\
                , .{ c_type, pkg, alias_name });
                try out.print("}\n\n", .{});
            }
        }

        for (ns.classes) |class| {
            const class_name = escapeTypeName(class.name);
            // containsBitField: https://github.com/ziglang/zig/issues/1499
            if (!class.isOpaque() and !containsBitField(class.layout_elements)) {
                if (class.c_type) |c_type| {
                    try out.print("test $S {\n", .{class_name});
                    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                    try out.print(
                        \\const ExpectedType = c.$I;
                        \\const ActualType = $I.$I;
                        \\try std.testing.expect(@typeInfo(ExpectedType) == .Struct);
                        \\try checkCompatibility(ExpectedType, ActualType);
                        \\
                    , .{ c_type, pkg, class_name });
                    try out.print("}\n\n", .{});
                }
            }
            for (class.constructors) |constructor| {
                if (isConstructorTranslatable(constructor)) {
                    const constructor_name = try toCamelCase(allocator, constructor.name, "_");
                    defer allocator.free(constructor_name);
                    try createFunctionTest(constructor.c_identifier, pkg, class_name, constructor_name, &out);
                }
            }
            for (class.functions) |function| {
                if (isFunctionTranslatable(function)) {
                    const function_name = try toCamelCase(allocator, function.name, "_");
                    defer allocator.free(function_name);
                    try createFunctionTest(function.c_identifier, pkg, class_name, function_name, &out);
                }
            }
            for (class.methods) |method| {
                if (isMethodTranslatable(method)) {
                    const method_name = try toCamelCase(allocator, method.name, "_");
                    defer allocator.free(method_name);
                    try createMethodTest(method.c_identifier, pkg, class_name, method_name, &out);
                }
            }
        }

        for (ns.records) |record| {
            const record_name = escapeTypeName(record.name);
            // containsBitField: https://github.com/ziglang/zig/issues/1499
            if (!record.isOpaque() and !containsBitField(record.layout_elements)) {
                if (record.c_type) |c_type| {
                    try out.print("test $S {\n", .{record_name});
                    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                    try out.print(
                        \\const ExpectedType = c.$I;
                        \\const ActualType = $I.$I;
                        \\
                    , .{ c_type, pkg, record_name });
                    if (record.isPointer()) {
                        try out.print("try std.testing.expect(@typeInfo(ExpectedType) == .Pointer);\n", .{});
                    } else {
                        try out.print("try std.testing.expect(@typeInfo(ExpectedType) == .Struct);\n", .{});
                    }
                    try out.print("try checkCompatibility(ExpectedType, ActualType);\n", .{});
                    try out.print("}\n\n", .{});
                }
            }
            if (!record.isPointer()) {
                for (record.constructors) |constructor| {
                    if (isConstructorTranslatable(constructor)) {
                        const constructor_name = try toCamelCase(allocator, constructor.name, "_");
                        defer allocator.free(constructor_name);
                        try createFunctionTest(constructor.c_identifier, pkg, record_name, constructor_name, &out);
                    }
                }
                for (record.functions) |function| {
                    if (isFunctionTranslatable(function)) {
                        const function_name = try toCamelCase(allocator, function.name, "_");
                        defer allocator.free(function_name);
                        try createFunctionTest(function.c_identifier, pkg, record_name, function_name, &out);
                    }
                }
                for (record.methods) |method| {
                    if (isMethodTranslatable(method)) {
                        const method_name = try toCamelCase(allocator, method.name, "_");
                        defer allocator.free(method_name);
                        try createMethodTest(method.c_identifier, pkg, record_name, method_name, &out);
                    }
                }
            }
        }

        for (ns.unions) |@"union"| {
            const union_name = escapeTypeName(@"union".name);
            if (!@"union".isOpaque()) {
                if (@"union".c_type) |c_type| {
                    try out.print("test $S {\n", .{union_name});
                    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                    try out.print(
                        \\const ExpectedType = c.$I;
                        \\const ActualType = $I.$I;
                        \\try std.testing.expect(@typeInfo(ExpectedType) == .Union);
                        \\try checkCompatibility(ExpectedType, ActualType);
                        \\
                    , .{ c_type, pkg, union_name });
                    try out.print("}\n\n", .{});
                }
            }
            for (@"union".constructors) |constructor| {
                if (isConstructorTranslatable(constructor)) {
                    const constructor_name = try toCamelCase(allocator, constructor.name, "_");
                    defer allocator.free(constructor_name);
                    try createFunctionTest(constructor.c_identifier, pkg, union_name, constructor_name, &out);
                }
            }
            for (@"union".functions) |function| {
                if (isFunctionTranslatable(function)) {
                    const function_name = try toCamelCase(allocator, function.name, "_");
                    defer allocator.free(function_name);
                    try createFunctionTest(function.c_identifier, pkg, union_name, function_name, &out);
                }
            }
            for (@"union".methods) |method| {
                if (isMethodTranslatable(method)) {
                    const method_name = try toCamelCase(allocator, method.name, "_");
                    defer allocator.free(method_name);
                    try createMethodTest(method.c_identifier, pkg, union_name, method_name, &out);
                }
            }
        }

        for (ns.bit_fields) |bit_field| {
            const bit_field_name = escapeTypeName(bit_field.name);
            if (bit_field.c_type) |c_type| {
                try out.print("test $S {\n", .{bit_field_name});
                try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                try out.print(
                    \\const ExpectedType = c.$I;
                    \\const ActualType = $I.$I;
                    \\try std.testing.expect(@typeInfo(ExpectedType) == .Int);
                    \\try checkCompatibility(ExpectedType, ActualType);
                    \\
                , .{ c_type, pkg, bit_field_name });
                try out.print("}\n\n", .{});
            }
            for (bit_field.functions) |function| {
                if (isFunctionTranslatable(function)) {
                    const function_name = try toCamelCase(allocator, function.name, "_");
                    defer allocator.free(function_name);
                    try createFunctionTest(function.c_identifier, pkg, bit_field_name, function_name, &out);
                }
            }
        }

        for (ns.enums) |@"enum"| {
            const enum_name = escapeTypeName(@"enum".name);
            if (@"enum".c_type) |c_type| {
                try out.print("test $S {\n", .{enum_name});
                try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                try out.print(
                    \\const ExpectedType = c.$I;
                    \\const ActualType = $I.$I;
                    \\try std.testing.expect(@typeInfo(ExpectedType) == .Int);
                    \\try checkCompatibility(ExpectedType, ActualType);
                    \\
                , .{ c_type, pkg, enum_name });
                try out.print("}\n\n", .{});
            }
            for (@"enum".functions) |function| {
                if (isFunctionTranslatable(function)) {
                    const function_name = try toCamelCase(allocator, function.name, "_");
                    defer allocator.free(function_name);
                    try createFunctionTest(function.c_identifier, pkg, enum_name, function_name, &out);
                }
            }
        }

        for (ns.functions) |function| {
            if (!isFunctionTranslatable(function)) continue;
            const function_name = try toCamelCase(allocator, function.name, "_");
            defer allocator.free(function_name);
            try out.print("test $S {\n", .{function_name});
            try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{function.c_identifier});
            try out.print(
                \\const ExpectedFnType = @TypeOf(c.$I);
                \\const ActualFnType = @TypeOf($I.$I);
                \\try std.testing.expect(@typeInfo(ExpectedFnType) == .Fn);
                \\try checkCompatibility(ExpectedFnType, ActualFnType);
                \\
            , .{ function.c_identifier, pkg, function_name });
            try out.print("}\n\n", .{});
        }

        try bw.flush();
        try output_file.sync();
    }
}

fn createFunctionTest(
    c_name: []const u8,
    pkg_name: []const u8,
    container_name: []const u8,
    function_name: []const u8,
    out: anytype,
) !void {
    try out.print("test \"$L.$L\" {\n", .{ container_name, function_name });
    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_name});
    try out.print(
        \\const ExpectedFnType = @TypeOf(c.$I);
        \\const ActualFnType = @TypeOf($I.$I.Own.$I);
        \\try std.testing.expect(@typeInfo(ExpectedFnType) == .Fn);
        \\try checkCompatibility(ExpectedFnType, ActualFnType);
        \\
    , .{ c_name, pkg_name, container_name, function_name });
    try out.print("}\n\n", .{});
}

fn createMethodTest(
    c_name: []const u8,
    pkg_name: []const u8,
    container_name: []const u8,
    function_name: []const u8,
    out: anytype,
) !void {
    try out.print("test \"$L.$L\" {\n", .{ container_name, function_name });
    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_name});
    try out.print(
        \\const ExpectedFnType = @TypeOf(c.$I);
        \\const ActualType = $I.$I;
        \\const ActualFnType = @TypeOf(ActualType.OwnMethods(ActualType).$I);
        \\try std.testing.expect(@typeInfo(ExpectedFnType) == .Fn);
        \\try checkCompatibility(ExpectedFnType, ActualFnType);
        \\
    , .{ c_name, pkg_name, container_name, function_name });
    try out.print("}\n\n", .{});
}

fn containsBitField(layout_elements: []const gir.LayoutElement) bool {
    return for (layout_elements) |layout_element| {
        if (layout_element == .field and layout_element.field.bits != null) break true;
    } else false;
}

fn containsAnonymousField(layout_elements: []const gir.LayoutElement) bool {
    return for (layout_elements) |layout_element| {
        if (layout_element != .field) break true;
    } else false;
}
