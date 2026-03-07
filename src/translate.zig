const std = @import("std");
const ZigWriter = @import("ZigWriter.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualStrings = std.testing.expectEqualStrings;
const Dependencies = @import("main.zig").Dependencies;
const Diagnostics = @import("main.zig").Diagnostics;

const gir = @import("gir.zig");

const RepositoryMap = std.HashMap(gir.Include, gir.Repository, gir.Include.Context, std.hash_map.default_max_load_percentage);
const RepositorySet = std.HashMap(gir.Include, void, gir.Include.Context, std.hash_map.default_max_load_percentage);

const TranslationContext = struct {
    /// The namespaces in the current context, by (untranslated) name.
    namespaces: std.StringHashMapUnmanaged(Namespace),
    /// All C symbols in the current context, by identifier.
    c_symbols: std.StringHashMapUnmanaged(Symbol),
    arena: std.heap.ArenaAllocator,

    fn init(allocator: Allocator) TranslationContext {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .namespaces = .{},
            .c_symbols = .{},
            .arena = arena,
        };
    }

    fn deinit(ctx: TranslationContext) void {
        ctx.arena.deinit();
    }

    fn addRepositoryAndDependencies(ctx: *TranslationContext, repository: gir.Repository, repository_map: RepositoryMap) !void {
        const allocator = ctx.arena.allocator();
        var seen = RepositorySet.init(allocator);
        defer seen.deinit();
        var needed_deps: std.ArrayList(gir.Include) = .empty;
        defer needed_deps.deinit(allocator);
        try needed_deps.append(allocator, .{ .name = repository.namespace.name, .version = repository.namespace.version });
        while (needed_deps.pop()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                try seen.put(needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try ctx.addRepository(dep_repo);
                    try needed_deps.appendSlice(allocator, dep_repo.includes);
                }
            }
        }
    }

    fn addRepository(ctx: *TranslationContext, repository: gir.Repository) !void {
        const allocator = ctx.arena.allocator();

        var aliases = std.StringHashMap(gir.Alias).init(allocator);
        for (repository.namespace.aliases) |alias| {
            try aliases.put(alias.name.local, alias);
            if (alias.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .alias = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = alias.name.local,
                } });
            }
        }

        var classes = std.StringHashMap(gir.Class).init(allocator);
        for (repository.namespace.classes) |class| {
            try classes.put(class.name.local, class);
            if (class.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .class = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = class.name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, class.name.local, class.functions);
            try ctx.addConstructorSymbols(repository.namespace.name, class.name.local, class.constructors);
            try ctx.addMethodSymbols(repository.namespace.name, class.name.local, class.methods);
            try ctx.addConstantSymbols(repository.namespace.name, class.name.local, class.constants);
        }

        var interfaces = std.StringHashMap(gir.Interface).init(allocator);
        for (repository.namespace.interfaces) |interface| {
            try interfaces.put(interface.name.local, interface);
            if (interface.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .iface = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = interface.name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, interface.name.local, interface.functions);
            try ctx.addConstructorSymbols(repository.namespace.name, interface.name.local, interface.constructors);
            try ctx.addMethodSymbols(repository.namespace.name, interface.name.local, interface.methods);
            try ctx.addConstantSymbols(repository.namespace.name, interface.name.local, interface.constants);
        }

        var records = std.StringHashMap(gir.Record).init(allocator);
        for (repository.namespace.records) |record| {
            try records.put(record.name.local, record);
            if (record.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .@"struct" = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = record.name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, record.name.local, record.functions);
            try ctx.addConstructorSymbols(repository.namespace.name, record.name.local, record.constructors);
            try ctx.addMethodSymbols(repository.namespace.name, record.name.local, record.methods);
        }

        var unions = std.StringHashMap(gir.Union).init(allocator);
        for (repository.namespace.unions) |@"union"| {
            try unions.put(@"union".name.local, @"union");
            if (@"union".c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .@"struct" = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = @"union".name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, @"union".name.local, @"union".functions);
            try ctx.addConstructorSymbols(repository.namespace.name, @"union".name.local, @"union".constructors);
            try ctx.addMethodSymbols(repository.namespace.name, @"union".name.local, @"union".methods);
        }

        var bit_fields = std.StringHashMap(gir.BitField).init(allocator);
        for (repository.namespace.bit_fields) |bit_field| {
            try bit_fields.put(bit_field.name.local, bit_field);
            if (bit_field.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .flags = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = bit_field.name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, bit_field.name.local, bit_field.functions);
        }

        var enums = std.StringHashMap(gir.Enum).init(allocator);
        for (repository.namespace.enums) |@"enum"| {
            try enums.put(@"enum".name.local, @"enum");
            if (@"enum".c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .@"enum" = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = @"enum".name.local,
                } });
            }
            try ctx.addFunctionSymbols(repository.namespace.name, @"enum".name.local, @"enum".functions);
        }

        var constants = std.StringHashMap(gir.Constant).init(allocator);
        for (repository.namespace.constants) |constant| {
            try constants.put(constant.name, constant);
        }
        try ctx.addConstantSymbols(repository.namespace.name, null, repository.namespace.constants);

        var functions = std.StringHashMap(gir.Function).init(allocator);
        for (repository.namespace.functions) |function| {
            try functions.put(function.name, function);
        }
        try ctx.addFunctionSymbols(repository.namespace.name, null, repository.namespace.functions);

        var callbacks = std.StringHashMap(gir.Callback).init(allocator);
        for (repository.namespace.callbacks) |callback| {
            try callbacks.put(callback.name, callback);
            if (callback.c_type) |c_type| {
                try ctx.c_symbols.put(allocator, c_type, .{ .callback = .{
                    .ns = .{ .explicit = repository.namespace.name },
                    .name = callback.name,
                } });
            }
        }

        try ctx.namespaces.put(allocator, repository.namespace.name, .{
            .name = repository.namespace.name,
            .version = repository.namespace.version,
            .aliases = aliases.unmanaged,
            .classes = classes.unmanaged,
            .interfaces = interfaces.unmanaged,
            .records = records.unmanaged,
            .unions = unions.unmanaged,
            .bit_fields = bit_fields.unmanaged,
            .enums = enums.unmanaged,
            .functions = functions.unmanaged,
            .callbacks = callbacks.unmanaged,
            .constants = constants.unmanaged,
        });
    }

    fn addFunctionSymbols(ctx: *TranslationContext, ns: []const u8, container: ?[]const u8, functions: []const gir.Function) !void {
        for (functions) |function| {
            try ctx.c_symbols.put(ctx.arena.allocator(), function.c_identifier, .{ .func = .{
                .ns = .{ .explicit = ns },
                .container = container,
                .name = function.name,
            } });
        }
    }

    fn addConstructorSymbols(ctx: *TranslationContext, ns: []const u8, container: []const u8, constructors: []const gir.Constructor) !void {
        for (constructors) |constructor| {
            try ctx.c_symbols.put(ctx.arena.allocator(), constructor.c_identifier, .{ .ctor = .{
                .ns = .{ .explicit = ns },
                .container = container,
                .name = constructor.name,
            } });
        }
    }

    fn addMethodSymbols(ctx: *TranslationContext, ns: []const u8, container: []const u8, methods: []const gir.Method) !void {
        for (methods) |method| {
            try ctx.c_symbols.put(ctx.arena.allocator(), method.c_identifier, .{ .method = .{
                .ns = .{ .explicit = ns },
                .container = container,
                .name = method.name,
            } });
        }
    }

    fn addConstantSymbols(ctx: *TranslationContext, ns: []const u8, container: ?[]const u8, constants: []const gir.Constant) !void {
        for (constants) |constant| {
            if (constant.c_identifier) |c_identifier| {
                try ctx.c_symbols.put(ctx.arena.allocator(), c_identifier, .{ .@"const" = .{
                    .ns = .{ .explicit = ns },
                    .container = container,
                    .name = constant.name,
                } });
            }
        }
    }

    /// Returns whether the type with the given name is "object-like" in a
    /// GObject context. See the comment in `TranslateTypeOptions` for what
    /// "GObject context" means.
    fn isObjectType(ctx: TranslationContext, name: gir.Name) bool {
        const resolved_name = ctx.resolveAlias(name);
        if (resolved_name.ns) |ns| {
            const namespace = ctx.namespaces.get(ns) orelse return false;
            return namespace.classes.get(resolved_name.local) != null or
                namespace.interfaces.get(resolved_name.local) != null or
                namespace.records.get(resolved_name.local) != null or
                namespace.unions.get(resolved_name.local) != null;
        }
        return false;
    }

    /// Returns whether the type with the given name is actually a pointer
    /// (for example, a typedefed pointer). This mostly affects the translation
    /// of nullability (explicit or implied) for the type.
    fn isPointerType(ctx: TranslationContext, name: gir.Name) bool {
        const resolved_name = ctx.resolveAlias(name);
        if (resolved_name.ns) |ns| {
            const namespace = ctx.namespaces.get(ns) orelse return false;
            return (if (namespace.records.get(resolved_name.local)) |record| record.isPointer() else false) or
                namespace.callbacks.get(resolved_name.local) != null;
        }
        return false;
    }

    /// Resolves `name` until it no longer refers to an alias.
    fn resolveAlias(ctx: TranslationContext, name: gir.Name) gir.Name {
        var current_name = name;
        while (true) {
            const name_ns = current_name.ns orelse return current_name;
            const namespace = ctx.namespaces.get(name_ns) orelse return current_name;
            const alias = namespace.aliases.get(current_name.local) orelse return current_name;
            current_name = alias.type.name orelse return current_name;
        }
    }

    const Namespace = struct {
        name: []const u8,
        version: []const u8,
        aliases: std.StringHashMapUnmanaged(gir.Alias),
        classes: std.StringHashMapUnmanaged(gir.Class),
        interfaces: std.StringHashMapUnmanaged(gir.Interface),
        records: std.StringHashMapUnmanaged(gir.Record),
        unions: std.StringHashMapUnmanaged(gir.Union),
        bit_fields: std.StringHashMapUnmanaged(gir.BitField),
        enums: std.StringHashMapUnmanaged(gir.Enum),
        functions: std.StringHashMapUnmanaged(gir.Function),
        callbacks: std.StringHashMapUnmanaged(gir.Callback),
        constants: std.StringHashMapUnmanaged(gir.Constant),
    };
};

pub fn createBindings(
    allocator: Allocator,
    io: std.Io,
    repositories: []const gir.Repository,
    bindings_path: []const []const u8,
    extensions_path: []const []const u8,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) Allocator.Error!void {
    compat_module: {
        const compat_output_dir_path = try std.fs.path.join(allocator, &.{ output_dir_path, "compat" });
        defer allocator.free(compat_output_dir_path);
        std.Io.Dir.cwd().createDirPath(io, compat_output_dir_path) catch |err| {
            try diag.add("failed to create output directory {s}: {}", .{ compat_output_dir_path, err });
            break :compat_module;
        };

        const compat_file_path = try std.fs.path.join(allocator, &.{ compat_output_dir_path, "compat.zig" });
        defer allocator.free(compat_file_path);
        std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = compat_file_path,
            .data = @embedFile("compat.zig"),
        }) catch |err| {
            try diag.add("failed to write output file {s}: {}", .{ compat_file_path, err });
            break :compat_module;
        };
    }

    var repository_map = RepositoryMap.init(allocator);
    defer repository_map.deinit();
    for (repositories) |repo| {
        try repository_map.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);
        const module_output_dir_path = try std.fs.path.join(allocator, &.{ output_dir_path, module_name });
        defer allocator.free(module_output_dir_path);

        std.Io.Dir.cwd().createDirPath(io, module_output_dir_path) catch |err| {
            try diag.add("failed to create output directory {s}: {}", .{ module_output_dir_path, err });
            continue;
        };

        const manual_bindings = copyBindingsFile(
            allocator,
            io,
            repo.namespace.name,
            repo.namespace.version,
            bindings_path,
            module_output_dir_path,
            deps,
            diag,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.CopyFailed => {
                try diag.add("failed to translate {s}-{s}", .{ repo.namespace.name, repo.namespace.version });
                continue;
            },
        };

        copyExtensionsFile(
            allocator,
            io,
            repo.namespace.name,
            repo.namespace.version,
            extensions_path,
            module_output_dir_path,
            deps,
            diag,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.CopyFailed => {
                try diag.add("failed to translate {s}-{s}", .{ repo.namespace.name, repo.namespace.version });
                continue;
            },
        };

        if (!manual_bindings) {
            var ctx = TranslationContext.init(allocator);
            defer ctx.deinit();
            try ctx.addRepositoryAndDependencies(repo, repository_map);
            createRepositoryBindings(
                allocator,
                io,
                repo,
                repository_map,
                ctx,
                module_output_dir_path,
                deps,
                diag,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.TranslateFailed => {
                    try diag.add("failed to translate {s}-{s}", .{ repo.namespace.name, repo.namespace.version });
                    continue;
                },
            };
        }
    }
}

fn copyBindingsFile(
    allocator: Allocator,
    io: std.Io,
    name: []const u8,
    version: []const u8,
    bindings_dir_paths: []const []const u8,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) !bool {
    const bindings_name = try fileNameAlloc(allocator, name, version);
    defer allocator.free(bindings_name);
    const bindings_output_path = try std.fs.path.join(allocator, &.{ output_dir_path, bindings_name });
    defer allocator.free(bindings_output_path);

    for (bindings_dir_paths) |bindings_dir_path| {
        const bindings_path = try std.fs.path.join(allocator, &.{ bindings_dir_path, bindings_name });
        defer allocator.free(bindings_path);

        std.Io.Dir.cwd().copyFile(bindings_path, std.Io.Dir.cwd(), bindings_output_path, io, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {
                try diag.add("failed to copy bindings file {s}: {}", .{ bindings_path, err });
                return error.CopyFailed;
            },
        };
        try deps.add(bindings_output_path, &.{bindings_path});
        return true;
    }

    return false;
}

fn copyExtensionsFile(
    allocator: Allocator,
    io: std.Io,
    name: []const u8,
    version: []const u8,
    extensions_dir_paths: []const []const u8,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) !void {
    const extensions_name = try fileNameAlloc(allocator, name, version);
    defer allocator.free(extensions_name);
    const extensions_output_path = try std.fs.path.join(allocator, &.{ output_dir_path, "ext.zig" });
    defer allocator.free(extensions_output_path);

    for (extensions_dir_paths) |extensions_dir_path| {
        const extensions_path = try std.fs.path.join(allocator, &.{ extensions_dir_path, extensions_name });
        defer allocator.free(extensions_path);

        std.Io.Dir.cwd().copyFile(extensions_path, std.Io.Dir.cwd(), extensions_output_path, io, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {
                try diag.add("failed to copy extensions file {s}: {}", .{ extensions_path, err });
                return error.CopyFailed;
            },
        };
        try deps.add(extensions_output_path, &.{extensions_path});
        return;
    }

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = extensions_output_path, .data = "" }) catch |err| {
        try diag.add("failed to create extensions file {s}: {}", .{ extensions_output_path, err });
        return error.CopyFailed;
    };
}

fn createRepositoryBindings(
    allocator: Allocator,
    io: std.Io,
    repo: gir.Repository,
    repository_map: RepositoryMap,
    ctx: TranslationContext,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) !void {
    const source = try createRepositoryBindingsSource(
        allocator,
        repo,
        repository_map,
        ctx,
    );
    defer allocator.free(source);
    const file_name = try fileNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
    defer allocator.free(file_name);
    const output_path = try std.fs.path.join(allocator, &.{ output_dir_path, file_name });
    defer allocator.free(output_path);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = source }) catch |err| {
        try diag.add("failed to write output source file {s}: {}", .{ output_path, err });
        return error.TranslateFailed;
    };
    try deps.addRepository(output_path, repo);
}

fn createRepositoryBindingsSource(
    allocator: Allocator,
    repo: gir.Repository,
    repository_map: RepositoryMap,
    ctx: TranslationContext,
) Allocator.Error![]u8 {
    var out: ZigWriter = .init(allocator);
    defer out.deinit();

    try out.print("pub const ext = @import(\"ext.zig\");\n", .{});

    try translateIncludes(allocator, repo.namespace, repository_map, &out);
    try translateNamespace(allocator, repo.namespace, ctx, &out);

    return try out.toFormatted();
}

fn translateIncludes(allocator: Allocator, ns: gir.Namespace, repository_map: RepositoryMap, out: *ZigWriter) !void {
    // Having the current namespace in scope using the same name makes type
    // translation logic simpler (no need to know what namespace we're in)
    const ns_lower = try std.ascii.allocLowerString(allocator, ns.name);
    defer allocator.free(ns_lower);
    try out.print("const $I = @This();\n\n", .{ns_lower});

    // std is needed for std.builtin.VaList
    try out.print("const std = @import(\"std\");\n", .{});
    // compat is used by all modules for Zig cross-version compatibility.
    try out.print("const compat = @import(\"compat\");\n", .{});

    var seen = RepositorySet.init(allocator);
    defer seen.deinit();
    var needed_deps: std.ArrayList(gir.Include) = .empty;
    defer needed_deps.deinit(allocator);
    if (repository_map.get(.{ .name = ns.name, .version = ns.version })) |dep_repo| {
        try needed_deps.appendSlice(allocator, dep_repo.includes);
    }
    while (needed_deps.pop()) |needed_dep| {
        if (!seen.contains(needed_dep)) {
            const module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
            defer allocator.free(module_name);
            const alias = try std.ascii.allocLowerString(allocator, needed_dep.name);
            defer allocator.free(alias);
            try out.print("const $I = @import($S);\n", .{ alias, module_name });

            try seen.put(needed_dep, {});
            if (repository_map.get(needed_dep)) |dep_repo| {
                try needed_deps.appendSlice(allocator, dep_repo.includes);
            }
        }
    }
}

fn fileNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{f}.zig", .{fmtModuleName(name, version)});
}

fn moduleNameAlloc(allocator: Allocator, name: []const u8, version: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{f}", .{fmtModuleName(name, version)});
}

fn fmtModuleName(name: []const u8, version: []const u8) std.fmt.Alt(gir.Include, formatModuleName) {
    return .{
        .data = .{ .name = name, .version = version },
    };
}

fn formatModuleName(mod: gir.Include, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (mod.name) |c| try writer.writeByte(std.ascii.toLower(c));
    const version_major_end = mem.indexOfScalar(u8, mod.version, '.') orelse mod.version.len;
    try writer.writeAll(mod.version[0..version_major_end]);
}

fn translateNamespace(allocator: Allocator, ns: gir.Namespace, ctx: TranslationContext, out: *ZigWriter) !void {
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
        try translateConstant(allocator, constant, ctx, out);
    }

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\    std.testing.refAllDecls(ext);
        \\}
        \\
    , .{});
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, alias.documentation, ctx, out);
    try out.print("pub const $I = ", .{escapeTypeName(alias.name.local)});
    try translateType(allocator, alias.type, .{}, ctx, out);
    try out.print(";\n\n", .{});
}

fn translateClass(allocator: Allocator, class: gir.Class, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, class.documentation, ctx, out);
    const name = escapeTypeName(class.name.local);
    try out.print("pub const $I = ", .{name});
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
    } else {
        try out.print(
            \\pub const Class = opaque {
            \\    pub const Instance = $I;
            \\};
            \\
        , .{name});
    }

    if (!class.isOpaque()) {
        try translateLayoutElements(allocator, class.layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    try out.print("pub const virtual_methods = struct {\n", .{});
    for (class.virtual_methods) |virtual_method| {
        try translateVirtualMethod(allocator, virtual_method, name, "Class", ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const properties = struct{\n", .{});
    for (class.properties) |property| {
        try translateProperty(allocator, property, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const signals = struct{\n", .{});
    for (class.signals) |signal| {
        try translateSignal(allocator, signal, name, ctx, out);
    }
    try out.print("};\n\n", .{});

    for (class.constants) |constant| {
        try translateConstant(allocator, constant, ctx, out);
    }
    for (class.callbacks) |callback| {
        try translateCallback(allocator, callback, .{ .named = true }, ctx, out);
    }

    var function_names = std.StringHashMap(void).init(allocator);
    defer function_names.deinit();
    for (class.functions) |function| {
        try function_names.put(function.name, {});
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }
    for (class.constructors) |constructor| {
        try function_names.put(constructor.name, {});
        try translateConstructor(allocator, constructor, class.name, ctx, out);
    }
    for (class.methods) |method| {
        try function_names.put(method.name, {});
        try translateMethod(allocator, method, .{ .self_type = name }, ctx, out);
    }

    if (class.get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }
    if (!function_names.contains("ref")) {
        if (class.ref_func) |ref_func| {
            try translateRefFunction(allocator, "ref", ref_func, class.name, ctx, out);
        } else if (classDerivesFromObject(class, ctx)) {
            try translateRefFunction(allocator, "ref", "g_object_ref", class.name, ctx, out);
        }
    }
    if (!function_names.contains("unref")) {
        if (class.unref_func) |unref_func| {
            try translateRefFunction(allocator, "unref", unref_func, class.name, ctx, out);
        } else if (classDerivesFromObject(class, ctx)) {
            try translateRefFunction(allocator, "unref", "g_object_unref", class.name, ctx, out);
        }
    }

    try out.print(
        \\pub fn as(p_instance: *$I, comptime P_T: type) *P_T {
        \\    return gobject.ext.as(P_T, p_instance);
        \\}
        \\
    , .{name});

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

fn classDerivesFromObject(class: gir.Class, ctx: TranslationContext) bool {
    var current_class = class;
    while (true) {
        if (mem.eql(u8, current_class.name.ns.?, "GObject") and mem.eql(u8, current_class.name.local, "Object")) {
            return true;
        }
        const parent = current_class.parent orelse return false;
        const parent_ns = ctx.namespaces.get(parent.ns.?) orelse return false;
        current_class = parent_ns.classes.get(parent.local) orelse return false;
    }
}

fn translateInterface(allocator: Allocator, interface: gir.Interface, ctx: TranslationContext, out: *ZigWriter) !void {
    // interface type
    try translateDocumentation(allocator, interface.documentation, ctx, out);
    const name = escapeTypeName(interface.name.local);
    try out.print("pub const $I = opaque {\n", .{name});

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
    } else {
        try out.print(
            \\pub const Iface = opaque {
            \\    pub const Instance = $I;
            \\};
            \\
        , .{name});
    }

    try out.print("pub const virtual_methods = struct {\n", .{});
    for (interface.virtual_methods) |virtual_method| {
        try translateVirtualMethod(allocator, virtual_method, name, "Iface", ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const properties = struct{\n", .{});
    for (interface.properties) |property| {
        try translateProperty(allocator, property, ctx, out);
    }
    try out.print("};\n\n", .{});

    try out.print("pub const signals = struct{\n", .{});
    for (interface.signals) |signal| {
        try translateSignal(allocator, signal, name, ctx, out);
    }
    try out.print("};\n\n", .{});

    for (interface.constants) |constant| {
        try translateConstant(allocator, constant, ctx, out);
    }
    for (interface.callbacks) |callback| {
        try translateCallback(allocator, callback, .{ .named = true }, ctx, out);
    }

    var function_names = std.StringHashMap(void).init(allocator);
    defer function_names.deinit();
    for (interface.functions) |function| {
        try function_names.put(function.name, {});
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }
    for (interface.constructors) |constructor| {
        try function_names.put(constructor.name, {});
        try translateConstructor(allocator, constructor, interface.name, ctx, out);
    }
    for (interface.methods) |method| {
        try function_names.put(method.name, {});
        try translateMethod(allocator, method, .{ .self_type = name }, ctx, out);
    }

    if (interface.get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }
    if (!function_names.contains("ref") and interfaceDerivesFromObject(interface, ctx)) {
        try translateRefFunction(allocator, "ref", "g_object_ref", interface.name, ctx, out);
    }
    if (!function_names.contains("unref") and interfaceDerivesFromObject(interface, ctx)) {
        try translateRefFunction(allocator, "unref", "g_object_unref", interface.name, ctx, out);
    }

    try out.print(
        \\pub fn as(p_instance: *$I, comptime P_T: type) *P_T {
        \\    return gobject.ext.as(P_T, p_instance);
        \\}
        \\
    , .{name});

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

fn interfaceDerivesFromObject(interface: gir.Interface, ctx: TranslationContext) bool {
    if (interface.prerequisites.len == 0) return true; // See special case documented above in translateInterface
    for (interface.prerequisites) |prerequisite| {
        const prerequisite_ns = ctx.namespaces.get(prerequisite.name.ns.?) orelse continue;
        if (prerequisite_ns.classes.get(prerequisite.name.local)) |prerequisite_class| {
            if (classDerivesFromObject(prerequisite_class, ctx)) return true;
        }
        if (prerequisite_ns.interfaces.get(prerequisite.name.local)) |prerequisite_interface| {
            if (interfaceDerivesFromObject(prerequisite_interface, ctx)) return true;
        }
    }
    return false;
}

fn translateRecord(allocator: Allocator, record: gir.Record, ctx: TranslationContext, out: *ZigWriter) !void {
    // record type
    try translateDocumentation(allocator, record.documentation, ctx, out);
    const name = escapeTypeName(record.name.local);
    try out.print("pub const $I = ", .{name});
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
    try out.print("\n", .{});

    if (!record.isOpaque()) {
        try translateLayoutElements(allocator, record.layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    for (record.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }
    for (record.constructors) |constructor| {
        try translateConstructor(allocator, constructor, record.name, ctx, out);
    }
    for (record.methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = name }, ctx, out);
    }

    if (record.get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }

    if (record.is_gtype_struct_for != null) {
        try out.print(
            \\pub fn as(p_instance: *$I, comptime P_T: type) *P_T {
            \\    return gobject.ext.as(P_T, p_instance);
            \\}
            \\
        , .{name});
    }

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

fn translateUnion(allocator: Allocator, @"union": gir.Union, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, @"union".documentation, ctx, out);
    const name = escapeTypeName(@"union".name.local);
    try out.print("pub const $I = ", .{name});
    if (@"union".isOpaque()) {
        try out.print("opaque {\n", .{});
    } else {
        try out.print("extern union {\n", .{});
    }
    try out.print("\n", .{});

    if (!@"union".isOpaque()) {
        try translateLayoutElements(allocator, @"union".layout_elements, ctx, out);
        try out.print("\n", .{});
    }

    for (@"union".functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }
    for (@"union".constructors) |constructor| {
        try translateConstructor(allocator, constructor, @"union".name, ctx, out);
    }
    for (@"union".methods) |method| {
        try translateMethod(allocator, method, .{ .self_type = name }, ctx, out);
    }

    if (@"union".get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

fn translateLayoutElements(allocator: Allocator, layout_elements: []const gir.LayoutElement, ctx: TranslationContext, out: *ZigWriter) !void {
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
                try translateDocumentation(allocator, field.documentation, ctx, out);
                try out.print("f_$L: u$L,\n", .{ field.name, bits });
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
                try translateDocumentation(allocator, field.documentation, ctx, out);
                try out.print("f_$L: @compileError(\"can't translate bitfields unless backed by guint\"),\n", .{field.name});
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
                    try translateDocumentation(allocator, field.documentation, ctx, out);
                    try out.print("f_$L: ", .{field.name});
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

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, ctx: TranslationContext, out: *ZigWriter) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = true,
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = true,
        }, ctx, out),
        .callback => |callback| try translateCallback(allocator, callback, .{
            .nullable = true,
        }, ctx, out),
    }
}

fn translateBitField(allocator: Allocator, bit_field: gir.BitField, ctx: TranslationContext, out: *ZigWriter) !void {
    var members = [1]?gir.Member{null} ** 64;
    var needs_u64 = false;
    for (bit_field.members) |member| {
        if (member.value > 0) {
            if (member.value > std.math.maxInt(u32)) {
                needs_u64 = true;
            }
            const as_u64: u64 = @intCast(member.value);
            const pos = std.math.log2_int(u64, as_u64);
            // There are several bit fields who have members declared that are
            // not powers of 2. Those (and all other members) will be translated
            // as constants.
            if (std.math.pow(u64, 2, pos) == as_u64) {
                // For duplicate field names, only the first name is used
                if (members[pos] == null) {
                    members[pos] = member;
                }
            }
        }
    }

    var backing_int_buf: [16]u8 = undefined;
    const backing_int, const backing_int_signed, const backing_int_bits = if (bit_field.bits) |bits|
        .{
            std.fmt.bufPrint(&backing_int_buf, "u{}", .{bits}) catch unreachable,
            std.fmt.bufPrint(&backing_int_buf, "i{}", .{bits}) catch unreachable,
            bits,
        }
    else if (needs_u64)
        .{ "u64", "i64", 64 }
    else
        .{ "c_uint", "c_int", 32 };

    try translateDocumentation(allocator, bit_field.documentation, ctx, out);
    const name = escapeTypeName(bit_field.name.local);
    try out.print("pub const $I = packed struct($L) {\n", .{ name, backing_int });
    for (members, 0..) |maybe_member, i| {
        if (maybe_member) |member| {
            try out.print("$I: bool = false,\n", .{member.name});
        } else if (i < backing_int_bits) {
            try out.print("_padding$L: bool = false,\n", .{i});
        }
    }

    try out.print("\n", .{});
    // Some "bit field" types are also used as flags, and some specified values
    // may not be powers of two (such as Gst.DebugColorFlags). We also need to
    // keep track of duplicate members, since GstVideo-1.0 has multiple members
    // with the same name:
    // https://gitlab.gnome.org/GNOME/gobject-introspection/-/issues/264
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    for (bit_field.members) |member| {
        if (!seen.contains(member.name)) {
            try out.print("pub const flags_$L: $I = @bitCast(@as($L, $L));\n", .{
                member.name,
                name,
                if (member.value >= 0) backing_int else backing_int_signed,
                member.value,
            });
        }
        try seen.put(member.name, {});
    }

    for (bit_field.functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }

    if (bit_field.get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

fn translateEnum(allocator: Allocator, @"enum": gir.Enum, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, @"enum".documentation, ctx, out);
    const name = escapeTypeName(@"enum".name.local);

    var backing_int_buf: [16]u8 = undefined;
    const backing_int = if (@"enum".bits) |bits|
        std.fmt.bufPrint(&backing_int_buf, "u{}", .{bits}) catch unreachable
    else
        "c_int";

    try out.print("pub const $I = enum($L) {\n", .{ name, backing_int });

    // Zig does not allow enums to have multiple fields with the same value, so
    // we must translate any duplicate values as constants referencing the
    // "base" value
    var seen_values = std.AutoHashMap(i65, gir.Member).init(allocator);
    defer seen_values.deinit();
    var duplicate_members: std.ArrayList(gir.Member) = .empty;
    defer duplicate_members.deinit(allocator);
    for (@"enum".members) |member| {
        if (seen_values.get(member.value) == null) {
            try out.print("$I = $L,\n", .{ member.name, member.value });
            try seen_values.put(member.value, member);
        } else {
            try duplicate_members.append(allocator, member);
        }
    }
    try out.print("_,\n\n", .{});

    for (duplicate_members.items) |member| {
        try out.print("pub const $I = $I.$I;\n", .{ member.name, name, seen_values.get(member.value).?.name });
    }

    for (@"enum".functions) |function| {
        try translateFunction(allocator, function, .{ .self_type = name }, ctx, out);
    }

    if (@"enum".get_type) |get_type| {
        try translateGetTypeFunction(allocator, "get_g_object_type", get_type, ctx, out);
    }

    try out.print(
        \\
        \\test {
        \\    @setEvalBranchQuota(100_000);
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
    , .{});

    try out.print("};\n\n", .{});
}

const TranslateFunctionOptions = struct {
    self_type: ?[]const u8 = null,
};

fn isFunctionTranslatable(function: gir.Function) bool {
    return function.moved_to == null;
}

fn translateFunction(allocator: Allocator, function: gir.Function, options: TranslateFunctionOptions, ctx: TranslationContext, out: *ZigWriter) !void {
    if (!isFunctionTranslatable(function)) {
        return;
    }

    const fnName = try toCamelCase(allocator, function.name, '_');
    defer allocator.free(fnName);
    // There is a function named `dummy` declared in libxml2-2.0.gir which has
    // the same name and c_identifier. I don't know why it's there, or even if
    // it's a real function that exists in the library. But it's in the GIR, so
    // this translator has to account for it.
    const needs_rename = !std.mem.eql(u8, fnName, function.c_identifier);

    // extern declaration
    try translateDocumentation(allocator, function.documentation, ctx, out);
    if (!needs_rename) {
        try out.print("pub ", .{});
    }
    try out.print("extern fn $I(", .{function.c_identifier});
    try translateParameters(allocator, function.parameters, .{
        .self_type = options.self_type,
        .throws = function.throws,
    }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, function.return_value, .{
        .force_nullable = function.throws,
    }, ctx, out);
    try out.print(";\n", .{});

    // function rename
    if (needs_rename) {
        try out.print("pub const $I = $I;\n\n", .{ fnName, function.c_identifier });
    }
}

fn translateGetTypeFunction(allocator: Allocator, name: []const u8, c_identifier: []const u8, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateFunction(allocator, .{
        .name = name,
        .c_identifier = c_identifier,
        .parameters = &.{},
        .return_value = .{
            .type = .{ .simple = .{
                .name = .{ .ns = "GObject", .local = "Type" },
                .c_type = "GType",
            } },
        },
    }, .{}, ctx, out);
}

fn translateRefFunction(allocator: Allocator, name: []const u8, c_identifier: []const u8, container_name: gir.Name, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateFunction(allocator, .{
        .name = name,
        .c_identifier = c_identifier,
        .parameters = &.{
            .{
                .name = "self",
                .type = .{ .simple = .{
                    .name = container_name,
                    .c_type = "gpointer",
                } },
            },
        },
        .return_value = .{
            .type = .{ .simple = .{
                .name = .{ .ns = null, .local = "none" },
                .c_type = "void",
            } },
        },
    }, .{}, ctx, out);
}

fn isConstructorTranslatable(constructor: gir.Constructor) bool {
    return constructor.moved_to == null;
}

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, container_name: gir.Name, ctx: TranslationContext, out: *ZigWriter) !void {
    var effective_return_value = constructor.return_value;
    effective_return_value.type = switch (constructor.return_value.type) {
        // Some constructors are actually specified to return supertypes of the
        // actual type being constructed, e.g. most GTK constructors returning
        // gtk.Widget instead of the actual type. This is presumably to make the
        // C interface easier to use (fewer casts), but kills the nice type
        // safety we get in Zig. So, we assume that constructors should actually
        // return the type of their container.
        .simple => |simple| .{ .simple = .{
            .name = container_name,
            .c_type = simple.c_type,
        } },
        // There should not be any constructors returning arrays, but if there
        // are, for now, we won't correct the type due to uncertainty in the
        // intention.
        .array => |array| .{ .array = array },
    };

    try translateFunction(allocator, .{
        .name = constructor.name,
        .c_identifier = constructor.c_identifier,
        .moved_to = constructor.moved_to,
        .parameters = constructor.parameters,
        .return_value = effective_return_value,
        .throws = constructor.throws,
        .documentation = constructor.documentation,
    }, .{}, ctx, out);
}

fn isMethodTranslatable(method: gir.Method) bool {
    return method.moved_to == null;
}

fn translateMethod(allocator: Allocator, method: gir.Method, options: TranslateFunctionOptions, ctx: TranslationContext, out: *ZigWriter) !void {
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

fn translateVirtualMethod(allocator: Allocator, virtual_method: gir.VirtualMethod, type_name: []const u8, type_struct_name: []const u8, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, virtual_method.documentation, ctx, out);
    try out.print("pub const $I = struct {\n", .{virtual_method.name});

    const instance_type = "@typeInfo(@TypeOf(p_class)).pointer.child.Instance";

    try out.print("pub fn call(p_class: anytype, ", .{});
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{
        .force_nullable = virtual_method.throws,
    }, ctx, out);
    try out.print(" {\n", .{});
    try out.print("return gobject.ext.as($I.$I, p_class).f_$L.?(", .{ type_name, type_struct_name, virtual_method.name });
    for (virtual_method.parameters, 0..) |parameter, i| {
        if (parameter.instance) {
            try out.print("gobject.ext.as($I, ", .{type_name});
            try translateParameterName(allocator, parameter.name, out);
            try out.print(")", .{});
        } else {
            try translateParameterName(allocator, parameter.name, out);
        }
        if (virtual_method.throws or i < virtual_method.parameters.len - 1) {
            try out.print(", ", .{});
        }
    }
    if (virtual_method.throws) {
        try out.print("p_error", .{});
    }
    try out.print(");\n", .{});
    try out.print("}\n\n", .{});

    try out.print("pub fn implement(p_class: anytype, p_implementation: ", .{});
    try out.print("*const fn (", .{});
    try translateParameters(allocator, virtual_method.parameters, .{
        .self_type = instance_type,
        .throws = virtual_method.throws,
    }, ctx, out);
    try out.print(") callconv(.c) ", .{});
    try translateReturnValue(allocator, virtual_method.return_value, .{
        .force_nullable = virtual_method.throws,
    }, ctx, out);
    try out.print(") void {\n", .{});
    try out.print("gobject.ext.as($I.$I, p_class).f_$L = @ptrCast(p_implementation);\n", .{ type_name, type_struct_name, virtual_method.name });
    try out.print("}\n", .{});

    try out.print("};\n\n", .{});
}

fn translateProperty(allocator: Allocator, property: gir.Property, ctx: TranslationContext, out: *ZigWriter) !void {
    const name = try allocator.dupe(u8, property.name);
    defer allocator.free(name);
    mem.replaceScalar(u8, name, '-', '_');

    try translateDocumentation(allocator, property.documentation, ctx, out);
    try out.print("pub const $I = struct {\n", .{name});

    try out.print("pub const name = $S;\n\n", .{property.name});

    try out.print("pub const Type = ", .{});
    switch (property.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = true,
            .gobject_context = true,
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = true,
            .gobject_context = true,
        }, ctx, out),
    }
    try out.print(";\n", .{});

    try out.print("};\n\n", .{});
}

fn translateSignal(allocator: Allocator, signal: gir.Signal, type_name: []const u8, ctx: TranslationContext, out: *ZigWriter) !void {
    const name = try allocator.dupe(u8, signal.name);
    defer allocator.free(name);
    mem.replaceScalar(u8, name, '-', '_');

    try translateDocumentation(allocator, signal.documentation, ctx, out);
    try out.print("pub const $I = struct {\n", .{name});

    try out.print("pub const name = $S;\n\n", .{signal.name});

    try out.print("pub fn connect(p_instance: anytype, comptime P_Data: type, p_callback: ", .{});
    try out.print("*const fn (@TypeOf(p_instance)", .{});
    if (signal.parameters.len > 0) {
        try out.print(", ", .{});
    }
    try translateParameters(allocator, signal.parameters, .{
        .self_type = "@TypeOf(p_instance)",
        .gobject_context = true,
    }, ctx, out);
    try out.print(", P_Data) callconv(.c) ", .{});
    try translateReturnValue(allocator, signal.return_value, .{ .gobject_context = true }, ctx, out);
    try out.print(", p_data: P_Data, p_options: gobject.ext.ConnectSignalOptions(P_Data)) c_ulong {\n", .{});
    try out.print(
        \\return gobject.signalConnectClosureById(
        \\    @ptrCast(@alignCast(gobject.ext.as($I, p_instance))),
        \\    gobject.signalLookup($S, $I.getGObjectType()),
        \\    glib.quarkFromString(p_options.detail orelse null),
        \\    gobject.CClosure.new(@ptrCast(p_callback), p_data, @ptrCast(p_options.destroyData)),
        \\    @intFromBool(p_options.after),
        \\);
        \\
    , .{ type_name, signal.name, type_name });
    try out.print("}\n", .{});

    try out.print("};\n\n", .{});
}

fn translateConstant(allocator: Allocator, constant: gir.Constant, ctx: TranslationContext, out: *ZigWriter) !void {
    try translateDocumentation(allocator, constant.documentation, ctx, out);
    if (constant.type == .simple and constant.type.simple.name != null and mem.eql(u8, constant.type.simple.name.?.local, "utf8")) {
        try out.print("pub const $I = $S;\n", .{ constant.name, constant.value });
    } else {
        try out.print("pub const $I = $L;\n", .{ constant.name, constant.value });
    }
}

// See also the set of built-in type names in gir.zig. This map contains more
// entries because it also handles mappings from C types, not just GIR type
// names.
const builtins = std.StaticStringMap([]const u8).initComptime(.{
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
    .{ "long long", "c_longlong" },
    .{ "unsigned long long", "c_ulonglong" },
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
    .{ "time_t", "std.posix.time_t" },
    .{ "pid_t", "std.posix.pid_t" },
    .{ "uid_t", "std.posix.uid_t" },
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
    /// Whether this is the type of an output parameter of a function.
    callee_allocated: bool = false,
    /// Whether the type is being translated in a GObject-specific context, such
    /// as a signal or property, where types are often specified without any
    /// corresponding C type and in such a case are meant to be assumed to be
    /// pointers.
    gobject_context: bool = false,
    /// An override for the type name. This will be output in place of the name
    /// wherever the name would have been output.
    override_name: ?[]const u8 = null,
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

fn translateType(
    allocator: Allocator,
    @"type": gir.Type,
    options: TranslateTypeOptions,
    ctx: TranslationContext,
    out: *ZigWriter,
) Allocator.Error!void {
    if (@"type".nullable or (options.nullable and typeIsPointer(@"type", options.gobject_context, ctx))) {
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
        if (options.override_name) |override_name| {
            try out.print("$L", .{override_name});
        } else {
            try translateName(allocator, name, out);
        }
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
        return translateType(allocator, .{ .name = name, .c_type = pointer.element }, .{
            .gobject_context = options.gobject_context,
            .override_name = options.override_name,
        }, ctx, out);
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
    if (options.override_name) |override_name| {
        try out.print("$L", .{override_name});
    } else {
        try translateName(allocator, name, out);
    }
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
    try testTranslateType("std.posix.time_t", .{ .name = .{ .ns = null, .local = "glong" }, .c_type = "time_t" }, .{});
    try testTranslateType("std.posix.time_t", .{ .name = .{ .ns = null, .local = "time_t" }, .c_type = "time_t" }, .{});
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
    // Only possibly nullable types may actually be translated as optional
    try testTranslateType("usize", .{ .name = .{ .ns = null, .local = "guintptr" }, .c_type = "guintptr" }, .{ .nullable = true });
    try testTranslateType("?gobject.SignalCMarshaller", .{ .name = .{ .ns = "GObject", .local = "SignalCMarshaller" }, .c_type = "GSignalCMarshaller" }, .{ .nullable = true, .callback_names = &.{"GObject.SignalCMarshaller"} });
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
    // See the invalidated_properties parameter in Gio, which is unfortunately
    // not represented in GIR as an array type, inhibiting a good translation.
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
    // Name overrides are used for instance parameters
    try testTranslateType("*OverrideName", .{ .name = .{ .ns = "GObject", .local = "Object" }, .c_type = "GObject*" }, .{ .override_name = "OverrideName" });
    // Out parameters do not currently make any difference for translation of simple types
    try testTranslateType("*c_int", .{ .name = .{ .ns = null, .local = "gint" }, .c_type = "int*" }, .{ .callee_allocated = true });
}

const TestTranslateTypeOptions = struct {
    nullable: bool = false,
    callee_allocated: bool = false,
    gobject_context: bool = false,
    override_name: ?[]const u8 = null,
    is_pointer: ?bool = null,
    class_names: []const []const u8 = &.{},
    callback_names: []const []const u8 = &.{},

    fn initTranslationContext(options: TestTranslateTypeOptions, base_allocator: Allocator) !TranslationContext {
        var ctx = TranslationContext.init(base_allocator);
        const allocator = ctx.arena.allocator();
        for (options.class_names) |class_name| {
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
                .name = .{ .ns = ns_name, .local = local_name },
                .layout_elements = undefined,
                .get_type = undefined,
            });
        }
        for (options.callback_names) |callback_name| {
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

    fn toTranslateTypeOptions(options: TestTranslateTypeOptions) TranslateTypeOptions {
        return .{
            .nullable = options.nullable,
            .callee_allocated = options.callee_allocated,
            .gobject_context = options.gobject_context,
            .override_name = options.override_name,
        };
    }
};

fn testTranslateType(expected: []const u8, @"type": gir.Type, options: TestTranslateTypeOptions) !void {
    var ctx = try options.initTranslationContext(std.testing.allocator);
    defer ctx.deinit();

    var out: ZigWriter = .init(std.testing.allocator);
    defer out.deinit();
    try translateType(std.testing.allocator, @"type", options.toTranslateTypeOptions(), ctx, &out);
    try expectEqualStrings(expected, out.raw.items);
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

fn translateArrayType(allocator: Allocator, @"type": gir.ArrayType, options: TranslateTypeOptions, ctx: TranslationContext, out: *ZigWriter) !void {
    // This special case is useful for types like glib.Array which are
    // translated as array types even though they're not really arrays
    if (@"type".name != null and @"type".c_type != null) {
        return translateType(allocator, .{ .name = @"type".name, .c_type = @"type".c_type }, options, ctx, out);
    }

    if (options.nullable and arrayTypeIsPointer(@"type", options.gobject_context, ctx)) {
        try out.print("?", .{});
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
        if (options.callee_allocated) {
            // If this is a callee-allocated parameter, then the correct
            // interpretation of the array type is that the real type is a
            // _pointer_ to an array (i.e. the array is the output). So, we
            // have to force a single pointer here, and strip away one level of
            // pointer from the rest of the translation logic.
            if (pointer_type) |pointer| {
                try out.print("*", .{});
                pointer_type = parseCPointerType(pointer.element);
            }
        }

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
    // Found in vte_terminal_get_text
    try testTranslateArrayType("*glib.Array", .{
        .name = .{ .ns = "GLib", .local = "Array" },
        .c_type = "GArray*",
        .element = &.{
            .simple = .{ .name = .{ .ns = "Vte", .local = "CharAttributes" } },
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
    // Found in vte_terminal_event_check_regex_simple
    try testTranslateArrayType("[*][*:0]u8", .{
        .c_type = "char**",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "utf8" }, .c_type = "char*" },
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
    // Found in gdk_display_map_keycode
    try testTranslateArrayType("?*[*]gdk.KeymapKey", .{
        .c_type = "GdkKeymapKey**",
        .element = &.{
            .simple = .{ .name = .{ .ns = "Gdk", .local = "KeymapKey" }, .c_type = "GdkKeymapKey*" },
        },
    }, .{ .nullable = true, .callee_allocated = true });
    // Found in hb_tag_to_string
    try testTranslateArrayType("*[4]u8", .{
        .c_type = "char*",
        .fixed_size = 4,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "guint8" } },
        },
    }, .{ .callee_allocated = true });
    // Found in g_shell_parse_argv
    try testTranslateArrayType("*[*:null]?[*:0]u8", .{
        .c_type = "gchar***",
        .zero_terminated = true,
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "filename" }, .c_type = null },
        },
    }, .{ .callee_allocated = true });
    // Found in g_input_stream_read
    try testTranslateArrayType("[*]u8", .{
        .c_type = "void*",
        .element = &.{
            .simple = .{ .name = .{ .ns = null, .local = "guint8" } },
        },
    }, .{});
}

fn testTranslateArrayType(expected: []const u8, @"type": gir.ArrayType, options: TestTranslateTypeOptions) !void {
    var ctx = try options.initTranslationContext(std.testing.allocator);
    defer ctx.deinit();

    var out: ZigWriter = .init(std.testing.allocator);
    defer out.deinit();
    try translateArrayType(std.testing.allocator, @"type", options.toTranslateTypeOptions(), ctx, &out);
    try expectEqualStrings(expected, out.raw.items);
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

fn translateCallback(allocator: Allocator, callback: gir.Callback, options: TranslateCallbackOptions, ctx: TranslationContext, out: *ZigWriter) !void {
    if (options.named) {
        try translateDocumentation(allocator, callback.documentation, ctx, out);
        try out.print("pub const $I = ", .{escapeTypeName(callback.name)});
    }

    if (options.nullable) {
        try out.print("?", .{});
    }
    try out.print("*const fn (", .{});
    try translateParameters(allocator, callback.parameters, .{ .throws = callback.throws }, ctx, out);
    try out.print(") callconv(.c) ", .{});
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, .{
            .nullable = callback.return_value.nullable or callback.throws,
        }, ctx, out),
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = callback.return_value.nullable or callback.throws,
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

fn translateParameters(allocator: Allocator, parameters: []const gir.Parameter, options: TranslateParametersOptions, ctx: TranslationContext, out: *ZigWriter) !void {
    // GIR does not appear to consider the instance-parameter when numbering
    // parameters for closure metadata
    const param_offset: usize = if (parameters.len > 0 and parameters[0].instance) 1 else 0;
    var force_nullable = std.AutoHashMap(usize, void).init(allocator);
    defer force_nullable.deinit();
    for (parameters) |parameter| {
        // The checks to ensure the referenced type is a pointer are due to the
        // closure and destroy attributes sometimes being used incorrectly:
        // https://gitlab.gnome.org/GNOME/gobject-introspection/-/issues/285
        if (parameter.closure) |closure| {
            const idx = closure + param_offset;
            if (idx < parameters.len) {
                try force_nullable.put(closure + param_offset, {});
            }
        }
        if (parameter.destroy) |destroy| {
            const idx = destroy + param_offset;
            if (idx < parameters.len) {
                try force_nullable.put(destroy + param_offset, {});
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

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, options: TranslateParameterOptions, ctx: TranslationContext, out: *ZigWriter) !void {
    if (parameter.type == .varargs) {
        try out.print("...", .{});
        return;
    }

    try translateParameterName(allocator, parameter.name, out);
    try out.print(": ", .{});
    switch (parameter.type) {
        .simple => |simple_type| {
            try translateType(allocator, simple_type, .{
                .nullable = options.force_nullable or parameter.isNullable(),
                .callee_allocated = parameter.isOut(),
                .gobject_context = options.gobject_context,
                .override_name = if (parameter.instance) options.self_type else null,
            }, ctx, out);
        },
        .array => |array_type| try translateArrayType(allocator, array_type, .{
            .nullable = options.force_nullable or parameter.isNullable(),
            .callee_allocated = parameter.isOut() and !parameter.caller_allocates,
            .gobject_context = options.gobject_context,
        }, ctx, out),
        .varargs => unreachable, // handled above
    }
}

fn translateParameterName(allocator: Allocator, parameter_name: []const u8, out: *ZigWriter) !void {
    const translated_name = try std.fmt.allocPrint(allocator, "p_{s}", .{parameter_name});
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

fn translateReturnValue(allocator: Allocator, return_value: gir.ReturnValue, options: TranslateReturnValueOptions, ctx: TranslationContext, out: *ZigWriter) !void {
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

/// A symbol that can be linked to in documentation.
///
/// Corresponds to the [qualifier fragments supported by
/// gi-docgen](https://gnome.pages.gitlab.gnome.org/gi-docgen/linking.html).
const Symbol = union(enum) {
    alias: TopLevel,
    callback: TopLevel,
    class: TopLevel,
    @"const": Member,
    ctor: Member,
    @"enum": TopLevel,
    @"error": TopLevel,
    flags: TopLevel,
    func: Member,
    iface: TopLevel,
    method: Member,
    property: Member,
    signal: Member,
    @"struct": TopLevel,
    vfunc: Member,
    type: TopLevel,
    id: []const u8,

    const Namespace = union(enum) {
        implicit,
        explicit: []const u8,
    };

    const TopLevel = struct {
        ns: Namespace,
        name: []const u8,
    };

    const Member = struct {
        ns: Namespace,
        container: ?[]const u8,
        name: []const u8,
    };

    fn parse(link: []const u8, ctx: TranslationContext) ?Symbol {
        const at_pos = mem.indexOfScalar(u8, link, '@') orelse return null;
        const fragment = link[0..at_pos];
        const argument = link[at_pos + 1 ..];
        if (mem.eql(u8, fragment, "alias")) {
            return .{ .alias = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "callback")) {
            return .{ .callback = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "class")) {
            return .{ .class = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "const")) {
            return .{ .@"const" = parseMember(argument, ctx) };
        } else if (mem.eql(u8, fragment, "ctor")) {
            return .{ .ctor = parseMember(argument, ctx) };
        } else if (mem.eql(u8, fragment, "enum")) {
            return .{ .@"enum" = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "error")) {
            return .{ .@"error" = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "flags")) {
            return .{ .flags = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "func")) {
            return .{ .func = parseMember(argument, ctx) };
        } else if (mem.eql(u8, fragment, "iface")) {
            return .{ .iface = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "method")) {
            return .{ .method = parseMember(argument, ctx) };
        } else if (mem.eql(u8, fragment, "property")) {
            return .{ .property = parseProperty(argument) orelse return null };
        } else if (mem.eql(u8, fragment, "signal")) {
            return .{ .signal = parseSignal(argument) orelse return null };
        } else if (mem.eql(u8, fragment, "struct")) {
            return .{ .@"struct" = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "vfunc")) {
            return .{ .vfunc = parseMember(argument, ctx) };
        } else if (mem.eql(u8, fragment, "type")) {
            return .{ .type = parseTopLevel(argument) };
        } else if (mem.eql(u8, fragment, "id")) {
            return .{ .id = argument };
        } else {
            return null;
        }
    }

    test parse {
        var ctx = TranslationContext.init(std.testing.allocator);
        defer ctx.deinit();
        try ctx.addRepository(.{
            .path = "Gtk-4.0.gir",
            .namespace = .{
                .name = "Gtk",
                .version = "4.0",
            },
            .arena = undefined, // Fine since we're not attempting to deinit this
        });

        try expectEqualDeep(Symbol{ .class = .{
            .ns = .implicit,
            .name = "Window",
        } }, parse("class@Window", ctx));
        try expectEqualDeep(Symbol{ .class = .{
            .ns = .{ .explicit = "Gtk" },
            .name = "Window",
        } }, parse("class@Gtk.Window", ctx));
        try expectEqualDeep(Symbol{ .method = .{
            .ns = .implicit,
            .container = "Widget",
            .name = "show",
        } }, parse("method@Widget.show", ctx));
        try expectEqualDeep(Symbol{ .method = .{
            .ns = .{ .explicit = "Gtk" },
            .container = "Widget",
            .name = "show",
        } }, parse("method@Gtk.Widget.show", ctx));
        try expectEqualDeep(Symbol{ .func = .{
            .ns = .implicit,
            .container = null,
            .name = "init",
        } }, parse("func@init", ctx));
        try expectEqualDeep(Symbol{ .func = .{
            .ns = .{ .explicit = "Gtk" },
            .container = null,
            .name = "init",
        } }, parse("func@Gtk.init", ctx));
        try expectEqualDeep(Symbol{ .property = .{
            .ns = .implicit,
            .container = "Orientable",
            .name = "orientation",
        } }, parse("property@Orientable:orientation", ctx));
        try expectEqualDeep(Symbol{ .property = .{
            .ns = .{ .explicit = "Gtk" },
            .container = "Orientable",
            .name = "orientation",
        } }, parse("property@Gtk.Orientable:orientation", ctx));
        try expectEqualDeep(Symbol{ .signal = .{
            .ns = .implicit,
            .container = "RecentManager",
            .name = "changed",
        } }, parse("signal@RecentManager::changed", ctx));
        try expectEqualDeep(Symbol{ .signal = .{
            .ns = .{ .explicit = "Gtk" },
            .container = "RecentManager",
            .name = "changed",
        } }, parse("signal@Gtk.RecentManager::changed", ctx));
        try expectEqualDeep(Symbol{ .id = "gtk_window_new" }, parse("id@gtk_window_new", ctx));
    }

    fn parseTopLevel(argument: []const u8) TopLevel {
        if (mem.indexOfScalar(u8, argument, '.')) |dot_pos| {
            return .{
                .ns = .{ .explicit = argument[0..dot_pos] },
                .name = argument[dot_pos + 1 ..],
            };
        } else {
            return .{
                .ns = .implicit,
                .name = argument,
            };
        }
    }

    fn parseMember(argument: []const u8, ctx: TranslationContext) Member {
        const first_dot_pos = mem.indexOfScalar(u8, argument, '.') orelse return .{
            .ns = .implicit,
            .container = null,
            .name = argument,
        };
        if (mem.indexOfScalarPos(u8, argument, first_dot_pos + 1, '.')) |second_dot_pos| {
            return .{
                .ns = .{ .explicit = argument[0..first_dot_pos] },
                .container = argument[first_dot_pos + 1 .. second_dot_pos],
                .name = argument[second_dot_pos + 1 ..],
            };
        }
        const first_part = argument[0..first_dot_pos];
        const second_part = argument[first_dot_pos + 1 ..];
        if (ctx.namespaces.contains(first_part)) {
            return .{
                .ns = .{ .explicit = first_part },
                .container = null,
                .name = second_part,
            };
        } else {
            return .{
                .ns = .implicit,
                .container = first_part,
                .name = second_part,
            };
        }
    }

    fn parseProperty(argument: []const u8) ?Member {
        const ns: Namespace, const rest = if (mem.indexOfScalar(u8, argument, '.')) |dot_pos|
            .{ .{ .explicit = argument[0..dot_pos] }, argument[dot_pos + 1 ..] }
        else
            .{ .implicit, argument };
        const sep_pos = mem.indexOfScalar(u8, rest, ':') orelse return null;
        return .{
            .ns = ns,
            .container = rest[0..sep_pos],
            .name = rest[sep_pos + 1 ..],
        };
    }

    fn parseSignal(argument: []const u8) ?Member {
        const ns: Namespace, const rest = if (mem.indexOfScalar(u8, argument, '.')) |dot_pos|
            .{ .{ .explicit = argument[0..dot_pos] }, argument[dot_pos + 1 ..] }
        else
            .{ .implicit, argument };
        const sep_pos = mem.indexOf(u8, rest, "::") orelse return null;
        return .{
            .ns = ns,
            .container = rest[0..sep_pos],
            .name = rest[sep_pos + "::".len ..],
        };
    }
};

comptime {
    _ = Symbol; // Ensure nested tests are run
}

fn translateDocumentation(allocator: Allocator, documentation: ?gir.Documentation, ctx: TranslationContext, out: *ZigWriter) !void {
    if (documentation) |doc| {
        var lines = mem.splitScalar(u8, doc.text, '\n');
        while (lines.next()) |line| {
            try out.print("/// ", .{});

            const trimmed_line = mem.trim(u8, line, &std.ascii.whitespace);
            if (mem.startsWith(u8, trimmed_line, "|[")) {
                // The language tag (if any) is currently ignored.
                try out.print("```\n", .{});
                continue;
            } else if (mem.eql(u8, trimmed_line, "]|")) {
                try out.print("```\n", .{});
                continue;
            } else if (mem.startsWith(u8, trimmed_line, "#")) heading: {
                const heading_content_start = mem.indexOfNone(u8, trimmed_line, "#") orelse trimmed_line.len;
                if (!mem.startsWith(u8, trimmed_line[heading_content_start..], " ")) break :heading;
                // Remove any heading anchor that might be present.
                const heading_end = mem.indexOfScalarPos(u8, trimmed_line, heading_content_start, '#') orelse trimmed_line.len;
                try out.print("$L\n", .{trimmed_line[0..heading_end]});
                continue;
            }

            var start: usize = 0;
            var pos = start;
            while (pos < line.len) : (pos += 1) {
                switch (line[pos]) {
                    '\\' => pos += 1,
                    '[' => {
                        const link_end = mem.indexOfScalarPos(u8, line, pos, ']') orelse continue;
                        if (link_end + 1 < line.len and line[link_end + 1] == '(') continue; // Normal Markdown link
                        var link_content = line[pos + 1 .. link_end];
                        if (link_content.len >= 2 and
                            link_content[0] == '`' and
                            link_content[link_content.len - 1] == '`')
                        {
                            link_content = link_content[1 .. link_content.len - 1];
                        }
                        const symbol = Symbol.parse(link_content, ctx) orelse continue;
                        try out.print("$L", .{line[start..pos]});
                        try out.print("`", .{});
                        try translateSymbolLink(allocator, symbol, ctx, out);
                        try out.print("`", .{});
                        start = link_end + 1;
                        pos = link_end;
                    },
                    '@' => {
                        pos += 1;
                        const param_start = pos;
                        while (pos < line.len) : (pos += 1) {
                            switch (line[pos]) {
                                'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
                                else => break,
                            }
                        }
                        const param_end = pos;
                        pos -= 1;
                        const param = line[param_start..param_end];
                        if (param.len == 0) continue;
                        try out.print("$L", .{line[start .. param_start - 1]});

                        try out.print("`$L`", .{param});
                        start = param_end;
                    },
                    '%' => {
                        pos += 1;
                        const symbol_start = pos;
                        while (pos < line.len) : (pos += 1) {
                            switch (line[pos]) {
                                'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
                                else => break,
                            }
                        }
                        const symbol_end = pos;
                        pos -= 1;
                        const symbol = line[symbol_start..symbol_end];
                        if (symbol.len == 0) continue;
                        try out.print("$L", .{line[start .. symbol_start - 1]});

                        if (ctx.c_symbols.get(symbol)) |resolved| {
                            try out.print("`", .{});
                            try translateSymbolLink(allocator, resolved, ctx, out);
                            try out.print("`", .{});
                        } else {
                            try out.print("`$I`", .{symbol});
                        }
                        start = symbol_end;
                    },
                    '#' => {
                        pos += 1;
                        const symbol_start = pos;
                        while (pos < line.len) : (pos += 1) {
                            switch (line[pos]) {
                                'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
                                else => break,
                            }
                        }
                        const symbol_end = pos;
                        const symbol = line[symbol_start..symbol_end];
                        if (symbol.len == 0) {
                            pos -= 1;
                            continue;
                        }
                        try out.print("$L", .{line[start .. symbol_start - 1]});

                        if (ctx.c_symbols.get(symbol)) |resolved| {
                            try out.print("`", .{});
                            try translateSymbolLink(allocator, resolved, ctx, out);
                        } else {
                            try out.print("`$I", .{symbol});
                        }

                        const RefType = enum {
                            member,
                            signal,
                            property,
                        };
                        const ref_type: RefType = if (mem.startsWith(u8, line[pos..], ".")) rt: {
                            pos += 1;
                            break :rt .member;
                        } else if (mem.startsWith(u8, line[pos..], "::")) rt: {
                            pos += 2;
                            break :rt .signal;
                        } else if (mem.startsWith(u8, line[pos..], ":")) rt: {
                            pos += 1;
                            break :rt .property;
                        } else {
                            pos -= 1;
                            try out.print("`", .{});
                            start = symbol_end;
                            continue;
                        };

                        const rest_start = pos;
                        while (pos < line.len) : (pos += 1) {
                            switch (line[pos]) {
                                'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
                                else => break,
                            }
                        }
                        var rest_end = pos;
                        const rest = line[rest_start..rest_end];
                        if (rest.len == 0) {
                            pos -= 1;
                            start = pos; // We still need to process the terminator character.
                            try out.print("`", .{});
                            continue;
                        }

                        switch (ref_type) {
                            .member => {
                                if (mem.startsWith(u8, line[pos..], "()")) {
                                    pos += 2;
                                    rest_end += 2;
                                    try out.print(".virtual_methods.$I`", .{rest});
                                } else {
                                    try out.print(".$I`", .{rest});
                                }
                            },
                            .signal => try out.print(".signals.$I`", .{rest}),
                            .property => try out.print(".properties.$I`", .{rest}),
                        }

                        pos -= 1;
                        start = rest_end;
                    },
                    '(' => {
                        if (pos + 1 == line.len or line[pos + 1] != ')') continue;
                        const func_end = pos;
                        var func_start = pos;
                        while (func_start > 0) : (func_start -= 1) {
                            switch (line[func_start - 1]) {
                                'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
                                else => break,
                            }
                        }
                        const func = line[func_start..func_end];
                        if (func.len == 0) continue;
                        if (func_start > start) {
                            try out.print("$L", .{line[start..func_start]});
                        }

                        if (ctx.c_symbols.get(func)) |resolved| {
                            try out.print("`", .{});
                            try translateSymbolLink(allocator, resolved, ctx, out);
                            try out.print("`", .{});
                        } else {
                            try out.print("`$I`", .{func});
                        }

                        pos += 1;
                        start = func_end + "()".len;
                    },
                    else => {},
                }
            }
            try out.print("$L", .{line[start..]});

            try out.print("\n", .{});
        }
    }
}

fn translateSymbolLink(allocator: Allocator, symbol: Symbol, ctx: TranslationContext, out: *ZigWriter) !void {
    switch (symbol) {
        .alias,
        .callback,
        .class,
        .@"enum",
        .@"error",
        .flags,
        .iface,
        .@"struct",
        .type,
        => |top_level| {
            switch (top_level.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            try out.print("$I", .{top_level.name});
        },

        .@"const",
        => |member| {
            switch (member.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            if (member.container) |container| {
                try out.print("$I.", .{container});
            }
            try out.print("$I", .{member.name});
        },

        .ctor,
        .func,
        .method,
        => |func| {
            switch (func.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            if (func.container) |container| {
                try out.print("$I.", .{container});
            }
            const func_name = try toCamelCase(allocator, func.name, '_');
            defer allocator.free(func_name);
            try out.print("$I", .{func_name});
        },

        .property => |property| {
            switch (property.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            if (property.container) |container| {
                try out.print("$I.", .{container});
            }
            const property_name = try allocator.dupe(u8, property.name);
            defer allocator.free(property_name);
            mem.replaceScalar(u8, property_name, '-', '_');
            try out.print("properties.$I", .{property_name});
        },

        .signal => |signal| {
            switch (signal.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            if (signal.container) |container| {
                try out.print("$I.", .{container});
            }
            const signal_name = try allocator.dupe(u8, signal.name);
            defer allocator.free(signal_name);
            mem.replaceScalar(u8, signal_name, '-', '_');
            try out.print("signals.$I", .{signal_name});
        },

        .vfunc => |func| {
            switch (func.ns) {
                .implicit => {},
                .explicit => |ns| try translateNameNs(allocator, ns, out),
            }
            if (func.container) |container| {
                try out.print("$I.", .{container});
            }
            try out.print("virtual_methods.$I", .{func.name});
        },

        .id,
        => |id| {
            if (ctx.c_symbols.get(id)) |resolved| {
                assert(resolved != .id);
                try translateSymbolLink(allocator, resolved, ctx, out);
            } else {
                try out.print("$I", .{id});
            }
        },
    }
}

const type_name_escapes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Class", "Class_" },
    .{ "Iface", "Iface_" },
    .{ "Parent", "Parent_" },
    .{ "Implements", "Implements_" },
    .{ "Prerequisites", "Prerequisites_" },
});

/// Escapes a potentially problematic type name (such as Class) with an
/// alternative which will not collide with other names used in codegen.
fn escapeTypeName(name: []const u8) []const u8 {
    return type_name_escapes.get(name) orelse name;
}

fn translateName(allocator: Allocator, name: gir.Name, out: *ZigWriter) !void {
    try translateNameNs(allocator, name.ns, out);
    var local_parts = mem.splitScalar(u8, name.local, '.');
    try out.print("$I", .{escapeTypeName(local_parts.first())});
    while (local_parts.next()) |local_part| {
        try out.print(".$I", .{escapeTypeName(local_part)});
    }
}

fn translateNameNs(allocator: Allocator, nameNs: ?[]const u8, out: *ZigWriter) !void {
    if (nameNs != null) {
        const type_ns = try std.ascii.allocLowerString(allocator, nameNs.?);
        defer allocator.free(type_ns);
        try out.print("$I.", .{type_ns});
    }
}

fn toCamelCase(allocator: Allocator, name: []const u8, word_sep: u8) ![]u8 {
    var out: std.ArrayList(u8) = try .initCapacity(allocator, name.len);
    var words = mem.splitScalar(u8, name, word_sep);
    var i: usize = 0;
    while (words.next()) |word| {
        if (word.len > 0) {
            if (i == 0) {
                out.appendSliceAssumeCapacity(word);
            } else {
                out.appendAssumeCapacity(std.ascii.toUpper(word[0]));
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
    try testToCamelCase("hello", "hello", '-');
    try testToCamelCase("hello", "hello", '_');
    try testToCamelCase("helloWorld", "hello_world", '_');
    try testToCamelCase("helloWorld", "hello-world", '-');
    try testToCamelCase("helloWorldManyWords", "hello-world-many-words", '-');
    try testToCamelCase("helloWorldManyWords", "hello_world_many_words", '_');
    try testToCamelCase("__hidden", "__hidden", '-');
    try testToCamelCase("__hidden", "__hidden", '_');
}

fn testToCamelCase(expected: []const u8, input: []const u8, word_sep: u8) !void {
    const actual = try toCamelCase(std.testing.allocator, input, word_sep);
    defer std.testing.allocator.free(actual);
    try expectEqualStrings(expected, actual);
}

pub fn createBuildFiles(
    allocator: Allocator,
    io: std.Io,
    repositories: []const gir.Repository,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) Allocator.Error!void {
    std.Io.Dir.cwd().createDirPath(io, output_dir_path) catch |err|
        return diag.add("failed to create output directory {s}: {}", .{ output_dir_path, err });

    try createBuildZig(allocator, io, repositories, output_dir_path, deps, diag);
    try createBuildZon(allocator, io, output_dir_path, deps, diag);
    try createBuildHelpers(allocator, io, output_dir_path, deps, diag);
}

fn createBuildZig(
    allocator: Allocator,
    io: std.Io,
    repositories: []const gir.Repository,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) Allocator.Error!void {
    const output_path = try std.fs.path.join(allocator, &.{ output_dir_path, "build.zig" });
    defer allocator.free(output_path);

    var repository_map = RepositoryMap.init(allocator);
    defer repository_map.deinit();
    for (repositories) |repo| {
        try repository_map.put(.{ .name = repo.namespace.name, .version = repo.namespace.version }, repo);
    }

    {
        // We need a root source files for the docs to reference all the modules.
        const docs_root_dir = try std.fs.path.join(allocator, &.{ output_dir_path, "src", "root" });
        defer allocator.free(docs_root_dir);
        std.Io.Dir.cwd().createDirPath(io, docs_root_dir) catch |err|
            return diag.add("failed to create docs root module directory {s}: {}", .{ docs_root_dir, err });
        const docs_root_path = try std.fs.path.join(allocator, &.{ docs_root_dir, "root.zig" });
        defer allocator.free(docs_root_path);
        const docs_root_source = try createDocsRootSource(allocator, repositories);
        defer allocator.free(docs_root_source);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = docs_root_path, .data = docs_root_source }) catch |err|
            return diag.add("failed to write docs root module file {s}: {}", .{ docs_root_path, err });
    }

    const source = try createBuildZigSource(
        allocator,
        repositories,
        repository_map,
        output_path,
        deps,
    );
    defer allocator.free(source);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = source }) catch |err|
        return diag.add("failed to write {s}: {}", .{ output_path, err });
}

fn createDocsRootSource(
    allocator: Allocator,
    repositories: []const gir.Repository,
) Allocator.Error![]u8 {
    var out: ZigWriter = .init(allocator);
    defer out.deinit();
    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);
        try out.print("pub const $I = @import($S);\n", .{ module_name, module_name });
    }
    return try out.toFormatted();
}

fn createBuildZigSource(
    allocator: Allocator,
    repositories: []const gir.Repository,
    repository_map: RepositoryMap,
    output_path: []const u8,
    deps: *Dependencies,
) Allocator.Error![]u8 {
    var out: ZigWriter = .init(allocator);
    defer out.deinit();

    try out.print("$L\n", .{@embedFile("build/build_base.zig")});

    try out.print("pub fn build(b: *std.Build) void {\n", .{});
    try out.print(
        \\const target = b.standardTargetOptions(.{});
        \\const optimize = b.standardOptimizeOption(.{});
        \\
        \\const docs_step = b.step("docs", "Generate documentation");
        \\const test_step = b.step("test", "Run tests");
        \\
        \\const compat = b.createModule(.{
        \\    .root_source_file = b.path("src/compat/compat.zig"),
        \\    .target = target,
        \\    .optimize = optimize,
        \\});
        \\
        \\
    , .{});

    for (repositories) |repo| {
        try deps.addRepository(output_path, repo);

        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        try out.print(
            \\const $I = b.addModule($S, .{
            \\    .root_source_file = b.path(b.pathJoin(&.{ "src", $S, $S ++ ".zig" })),
            \\    .target = target,
            \\    .optimize = optimize,
            \\});
            \\
        , .{ module_name, module_name, module_name, module_name });

        try out.print("libraries.$I.linkTo($I);\n", .{ module_name, module_name });
        try out.print("$I.addImport(\"compat\", compat);\n\n", .{module_name});

        const test_name = try std.fmt.allocPrint(allocator, "{s}_test", .{module_name});
        defer allocator.free(test_name);

        // Unfortunately, GLib requires some special handling for testing. Some
        // of the functions in GLib require GObject to be linked, but we don't
        // really want to enforce GObject as a mandatory dependency of GLib,
        // since it's still possible to use GLib without GObject as long as
        // those functions aren't used.
        // As such, for GLib specifically, we create a hard-coded special test
        // module.
        if (mem.eql(u8, module_name, "glib2")) {
            try out.print(
                \\const glib2_test_mod = b.createModule(.{
                \\    .root_source_file = b.path("src/glib2/glib2.zig"),
                \\    .target = target,
                \\    .optimize = optimize,
                \\});
                \\libraries.glib2.linkTo(glib2_test_mod);
                \\libraries.gobject2.linkTo(glib2_test_mod);
                \\// Some deprecated thread functions require linking gthread-2.0
                \\glib2_test_mod.linkSystemLibrary("gthread-2.0", .{ .use_pkg_config = .force });
                \\glib2_test_mod.addImport("compat", compat);
                \\glib2_test_mod.addImport("glib2", glib2_test_mod);
                \\
                \\const $I = b.addTest(.{
                \\    .root_module = glib2_test_mod,
                \\});
                \\
            , .{test_name});
        } else {
            try out.print(
                \\const $I = b.addTest(.{
                \\    .root_module = $I,
                \\});
                \\
            , .{ test_name, module_name });
        }

        try out.print("test_step.dependOn(&b.addRunArtifact($I).step);\n\n", .{test_name});
    }

    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        var seen = RepositorySet.init(allocator);
        defer seen.deinit();
        var needed_deps: std.ArrayList(gir.Include) = .empty;
        defer needed_deps.deinit(allocator);
        if (repository_map.get(.{ .name = repo.namespace.name, .version = repo.namespace.version })) |dep_repo| {
            try needed_deps.appendSlice(allocator, dep_repo.includes);
        }
        while (needed_deps.pop()) |needed_dep| {
            if (!seen.contains(needed_dep)) {
                const dep_module_name = try moduleNameAlloc(allocator, needed_dep.name, needed_dep.version);
                defer allocator.free(dep_module_name);
                try out.print("$I.addImport($S, $I);\n", .{ module_name, dep_module_name, dep_module_name });

                try seen.put(needed_dep, {});
                if (repository_map.get(needed_dep)) |dep_repo| {
                    try needed_deps.appendSlice(allocator, dep_repo.includes);
                }
            }
        }

        // The self-dependency is useful for extensions files to be able to import their own module by name
        try out.print("$I.addImport($S, $I);\n", .{ module_name, module_name, module_name });
    }

    // Docs
    try out.print(
        \\const docs_mod = b.createModule(.{
        \\    .root_source_file = b.path("src/root/root.zig"),
        \\    .target = target,
        \\    .optimize = .Debug,
        \\});
        \\const docs_obj = b.addObject(.{
        \\    .name = "docs",
        \\    .root_module = docs_mod,
        \\    // Defaults to false to avoid bringing in the lazy dependency if not building docs.
        \\    .zig_lib_dir = if (b.option(bool, "autodoc-fork", "Use Autodoc fork for documentation") orelse false) zig_lib_dir: {
        \\        const zig_autodoc_dep = b.lazyDependency("zig_autodoc", .{}) orelse break :zig_lib_dir null;
        \\        break :zig_lib_dir zig_autodoc_dep.path("lib");
        \\    } else null,
        \\});
        \\const install_docs = b.addInstallDirectory(.{
        \\    .source_dir = docs_obj.getEmittedDocs(),
        \\    .install_dir = .prefix,
        \\    .install_subdir = "docs",
        \\});
        \\docs_step.dependOn(&install_docs.step);
        \\
    , .{});
    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);
        try out.print("docs_mod.addImport($S, $I);\n", .{ module_name, module_name });
    }

    try out.print("}\n\n", .{});

    try out.print("pub const libraries = struct {\n", .{});
    for (repositories) |repo| {
        const module_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(module_name);

        try out.print("pub const $I: Library = .{\n", .{module_name});

        try out.print(".system_libraries = &.{", .{});
        for (repo.packages, 0..) |package, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("$S", .{package.name});
        }
        try out.print("},\n", .{});

        try out.print("};\n\n", .{});
    }
    try out.print("};\n\n", .{});

    return try out.toFormatted();
}

fn createBuildZon(
    allocator: Allocator,
    io: std.Io,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) !void {
    const output_path = try std.fs.path.join(allocator, &.{ output_dir_path, "build.zig.zon" });
    defer allocator.free(output_path);

    try deps.add(output_path, &.{});

    const source =
        \\.{
        \\    .name = .gobject,
        \\    .version = "0.3.1",
        \\    .fingerprint = 0xca12a75aeca74b4a, // Changing this has security and trust implications.
        \\    .minimum_zig_version = "0.15.1",
        \\    .paths = .{
        \\        "build",
        \\        "src",
        \\        "build.zig",
        \\        "build.zig.zon",
        \\    },
        \\    .dependencies = .{
        \\        // Upstream Autodoc currently has a behavior where alias declarations
        \\        // are presented using the name of the underlying decl:
        \\        // https://github.com/ziglang/zig/issues/20905
        \\        // This is unusable for this library, because it means all our aliased
        \\        // functions would be given their original C names in the documentation.
        \\        .zig_autodoc = .{
        \\            .url = "git+https://github.com/ianprime0509/zig?ref=zig-gobject#f2696e399062de9f9ffba0ee1eac5411bcca90e8",
        \\            .hash = "zig-0.0.0-Fp4XJIbnIg33b41dbDFzgPZfQEbWITdlrryg8kEqYh5x",
        \\            .lazy = true,
        \\        },
        \\    },
        \\}
        \\
    ;

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = source }) catch |err|
        return diag.add("failed to write {s}: {}", .{ output_path, err });
}

fn createBuildHelpers(
    allocator: Allocator,
    io: std.Io,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) !void {
    const helper_dir_path = try std.fs.path.join(allocator, &.{ output_dir_path, "build" });
    defer allocator.free(helper_dir_path);
    std.Io.Dir.cwd().createDirPath(io, helper_dir_path) catch |err|
        return diag.add("failed to create output directory {s}: {}", .{ helper_dir_path, err });

    const helpers: []const []const u8 = &.{"build_gresources_xml.zig"};
    inline for (helpers) |helper| {
        const output_path = try std.fs.path.join(allocator, &.{ helper_dir_path, helper });
        defer allocator.free(output_path);

        try deps.add(output_path, &.{});

        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = @embedFile("build/" ++ helper) }) catch |err|
            return diag.add("failed to write {s}: {}", .{ output_path, err });
    }
}

pub fn createAbiTests(
    allocator: Allocator,
    io: std.Io,
    repositories: []const gir.Repository,
    output_dir_path: []const u8,
    deps: *Dependencies,
    diag: *Diagnostics,
) Allocator.Error!void {
    std.Io.Dir.cwd().createDirPath(io, output_dir_path) catch |err|
        return diag.add("failed to create output directory {s}: {}", .{ output_dir_path, err });

    {
        const compat_file_path = try std.fs.path.join(allocator, &.{ output_dir_path, "compat.zig" });
        defer allocator.free(compat_file_path);
        std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = compat_file_path,
            .data = @embedFile("compat.zig"),
        }) catch |err| {
            try diag.add("failed to write output file {s}: {}", .{ compat_file_path, err });
        };
    }

    for (repositories) |repo| {
        const import_name = try moduleNameAlloc(allocator, repo.namespace.name, repo.namespace.version);
        defer allocator.free(import_name);

        const source = try createAbiTestSource(allocator, repo, import_name);
        defer allocator.free(source);
        const file_name = try std.fmt.allocPrint(allocator, "{s}.abi.zig", .{import_name});
        defer allocator.free(file_name);
        const file_path = try std.fs.path.join(allocator, &.{ output_dir_path, file_name });
        defer allocator.free(file_path);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = source }) catch |err| {
            try diag.add("failed to write output source file {s}: {}", .{ file_path, err });
            try diag.add("failed to create ABI tests for {s}-{s}", .{ repo.namespace.name, repo.namespace.version });
        };
        try deps.addRepository(file_path, repo);
    }
}

fn createAbiTestSource(
    allocator: Allocator,
    repo: gir.Repository,
    import_name: []const u8,
) Allocator.Error![]u8 {
    var out: ZigWriter = .init(allocator);
    defer out.deinit();

    const ns = repo.namespace;
    const pkg = try std.ascii.allocLowerString(allocator, ns.name);
    defer allocator.free(pkg);

    try out.print("const c = @cImport({\n", .{});
    for (repo.c_includes) |c_include| {
        try out.print("@cInclude($S);\n", .{c_include.name});
    }
    try out.print("});\n", .{});
    try out.print("const std = @import(\"std\");\n", .{});
    try out.print("const compat = @import(\"compat.zig\");\n", .{});
    try out.print("const $I = @import($S);\n\n", .{ pkg, import_name });

    try out.print(
        \\fn checkCompatibility(comptime ExpectedType: type, comptime ActualType: type) !void {
        \\    // translate-c doesn't seem to want to translate va_list to std.builtin.VaList
        \\    if (ActualType == std.builtin.VaList) return;
        \\
        \\    const expected_type_info = @typeInfo(ExpectedType);
        \\    const actual_type_info = @typeInfo(ActualType);
        \\    switch (expected_type_info) {
        \\        .void => switch (actual_type_info) {
        \\            .void => {},
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        .bool => switch (actual_type_info) {
        \\            .bool => {},
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        .float => |expected_float| switch (actual_type_info) {
        \\            .float => |actual_float| try std.testing.expectEqual(expected_float.bits, actual_float.bits),
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        .array => |expected_array| switch (actual_type_info) {
        \\            .array => |actual_array| {
        \\                try std.testing.expectEqual(expected_array.len, actual_array.len);
        \\                try checkCompatibility(expected_array.child, actual_array.child);
        \\            },
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        .@"struct" => switch (actual_type_info) {
        \\            .@"struct" => {
        \\                try std.testing.expectEqual(@sizeOf(ExpectedType), @sizeOf(ActualType));
        \\                try std.testing.expectEqual(@alignOf(ExpectedType), @alignOf(ActualType));
        \\            },
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        .@"union" => switch (actual_type_info) {
        \\            .@"union" => {
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
        \\        .@"opaque" => {},
        \\        .int => |expected_int| switch (actual_type_info) {
        \\            // Checking signedness here turns out to be too strict for many cases
        \\            // and does not affect actual ABI compatibility.
        \\            .int => |actual_int| try std.testing.expectEqual(expected_int.bits, actual_int.bits),
        \\            .@"enum" => |actual_enum| try checkCompatibility(ExpectedType, actual_enum.tag_type),
        \\            .@"struct" => |actual_struct| {
        \\                try std.testing.expect(actual_struct.layout == .@"packed");
        \\                try checkCompatibility(ExpectedType, actual_struct.backing_integer.?);
        \\            },
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)});
        \\                return error.TestUnexpectedType;
        \\            },
        \\        },
        \\        // Pointers are tricky to assert on, since we may translate some pointers
        \\        // differently from how they appear in C (e.g. *GtkWindow rather than *GtkWidget)
        \\        .pointer => switch (actual_type_info) {
        \\            .pointer => {},
        \\            .@"optional" => |actual_optional| try std.testing.expect(@typeInfo(actual_optional.child) == .pointer),
        \\            else => {
        \\                std.debug.print("incompatible types: expected {s}, actual {s}\n", .{@typeName(ExpectedType), @typeName(ActualType)}) ;
        \\                return error.TestUnexpectedType;
        \\            }
        \\        },
        \\        .@"optional" => |expected_optional| switch (@typeInfo(expected_optional.child)) {
        \\            .pointer => try checkCompatibility(expected_optional.child, ActualType),
        \\            else => {
        \\                std.debug.print("unexpected C translated type: {s}\n", .{@typeName(ExpectedType)});
        \\                return error.TestUnexpectedType;
        \\            }
        \\        },
        \\        .@"fn" => |expected_fn| switch (actual_type_info) {
        \\            .@"fn" => |actual_fn| {
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
        const alias_name = escapeTypeName(alias.name.local);
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
        const class_name = escapeTypeName(class.name.local);
        // containsBitField: https://github.com/ziglang/zig/issues/1499
        if (!class.isOpaque() and !containsBitField(class.layout_elements)) {
            if (class.c_type) |c_type| {
                try out.print("test $S {\n", .{class_name});
                try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                try out.print(
                    \\const ExpectedType = c.$I;
                    \\const ActualType = $I.$I;
                    \\try std.testing.expect(@typeInfo(ExpectedType) == .@"struct");
                    \\try checkCompatibility(ExpectedType, ActualType);
                    \\
                , .{ c_type, pkg, class_name });
                try out.print("}\n\n", .{});
            }
        }
        for (class.constructors) |constructor| {
            if (isConstructorTranslatable(constructor)) {
                const constructor_name = try toCamelCase(allocator, constructor.name, '_');
                defer allocator.free(constructor_name);
                try createFunctionTest(constructor.c_identifier, pkg, class_name, constructor_name, &out);
            }
        }
        for (class.functions) |function| {
            if (isFunctionTranslatable(function)) {
                const function_name = try toCamelCase(allocator, function.name, '_');
                defer allocator.free(function_name);
                try createFunctionTest(function.c_identifier, pkg, class_name, function_name, &out);
            }
        }
        for (class.methods) |method| {
            if (isMethodTranslatable(method)) {
                const method_name = try toCamelCase(allocator, method.name, '_');
                defer allocator.free(method_name);
                try createMethodTest(method.c_identifier, pkg, class_name, method_name, &out);
            }
        }
    }

    for (ns.records) |record| {
        const record_name = escapeTypeName(record.name.local);
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
                    try out.print("try std.testing.expect(@typeInfo(ExpectedType) == .pointer);\n", .{});
                } else {
                    try out.print("try std.testing.expect(@typeInfo(ExpectedType) == .@\"struct\");\n", .{});
                }
                try out.print("try checkCompatibility(ExpectedType, ActualType);\n", .{});
                try out.print("}\n\n", .{});
            }
        }
        if (!record.isPointer()) {
            for (record.constructors) |constructor| {
                if (isConstructorTranslatable(constructor)) {
                    const constructor_name = try toCamelCase(allocator, constructor.name, '_');
                    defer allocator.free(constructor_name);
                    try createFunctionTest(constructor.c_identifier, pkg, record_name, constructor_name, &out);
                }
            }
            for (record.functions) |function| {
                if (isFunctionTranslatable(function)) {
                    const function_name = try toCamelCase(allocator, function.name, '_');
                    defer allocator.free(function_name);
                    try createFunctionTest(function.c_identifier, pkg, record_name, function_name, &out);
                }
            }
            for (record.methods) |method| {
                if (isMethodTranslatable(method)) {
                    const method_name = try toCamelCase(allocator, method.name, '_');
                    defer allocator.free(method_name);
                    try createMethodTest(method.c_identifier, pkg, record_name, method_name, &out);
                }
            }
        }
    }

    for (ns.unions) |@"union"| {
        const union_name = escapeTypeName(@"union".name.local);
        if (!@"union".isOpaque()) {
            if (@"union".c_type) |c_type| {
                try out.print("test $S {\n", .{union_name});
                try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
                try out.print(
                    \\const ExpectedType = c.$I;
                    \\const ActualType = $I.$I;
                    \\try std.testing.expect(@typeInfo(ExpectedType) == .@"union");
                    \\try checkCompatibility(ExpectedType, ActualType);
                    \\
                , .{ c_type, pkg, union_name });
                try out.print("}\n\n", .{});
            }
        }
        for (@"union".constructors) |constructor| {
            if (isConstructorTranslatable(constructor)) {
                const constructor_name = try toCamelCase(allocator, constructor.name, '_');
                defer allocator.free(constructor_name);
                try createFunctionTest(constructor.c_identifier, pkg, union_name, constructor_name, &out);
            }
        }
        for (@"union".functions) |function| {
            if (isFunctionTranslatable(function)) {
                const function_name = try toCamelCase(allocator, function.name, '_');
                defer allocator.free(function_name);
                try createFunctionTest(function.c_identifier, pkg, union_name, function_name, &out);
            }
        }
        for (@"union".methods) |method| {
            if (isMethodTranslatable(method)) {
                const method_name = try toCamelCase(allocator, method.name, '_');
                defer allocator.free(method_name);
                try createMethodTest(method.c_identifier, pkg, union_name, method_name, &out);
            }
        }
    }

    for (ns.bit_fields) |bit_field| {
        const bit_field_name = escapeTypeName(bit_field.name.local);
        if (bit_field.c_type) |c_type| {
            try out.print("test $S {\n", .{bit_field_name});
            try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
            try out.print(
                \\const ExpectedType = c.$I;
                \\const ActualType = $I.$I;
                \\try std.testing.expect(@typeInfo(ExpectedType) == .int);
                \\try checkCompatibility(ExpectedType, ActualType);
                \\
            , .{ c_type, pkg, bit_field_name });
            try out.print("}\n\n", .{});
        }
        for (bit_field.functions) |function| {
            if (isFunctionTranslatable(function)) {
                const function_name = try toCamelCase(allocator, function.name, '_');
                defer allocator.free(function_name);
                try createFunctionTest(function.c_identifier, pkg, bit_field_name, function_name, &out);
            }
        }
    }

    for (ns.enums) |@"enum"| {
        const enum_name = escapeTypeName(@"enum".name.local);
        if (@"enum".c_type) |c_type| {
            try out.print("test $S {\n", .{enum_name});
            try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_type});
            try out.print(
                \\const ExpectedType = c.$I;
                \\const ActualType = $I.$I;
                \\try std.testing.expect(@typeInfo(ExpectedType) == .int);
                \\try checkCompatibility(ExpectedType, ActualType);
                \\
            , .{ c_type, pkg, enum_name });
            try out.print("}\n\n", .{});
        }
        for (@"enum".functions) |function| {
            if (isFunctionTranslatable(function)) {
                const function_name = try toCamelCase(allocator, function.name, '_');
                defer allocator.free(function_name);
                try createFunctionTest(function.c_identifier, pkg, enum_name, function_name, &out);
            }
        }
    }

    for (ns.functions) |function| {
        if (!isFunctionTranslatable(function)) continue;
        const function_name = try toCamelCase(allocator, function.name, '_');
        defer allocator.free(function_name);
        try out.print("test $S {\n", .{function_name});
        try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{function.c_identifier});
        try out.print(
            \\const ExpectedFnType = @TypeOf(c.$I);
            \\const ActualFnType = @TypeOf($I.$I);
            \\try std.testing.expect(@typeInfo(ExpectedFnType) == .@"fn");
            \\try checkCompatibility(ExpectedFnType, ActualFnType);
            \\
        , .{ function.c_identifier, pkg, function_name });
        try out.print("}\n\n", .{});
    }

    return try out.toFormatted();
}

fn createFunctionTest(
    c_name: []const u8,
    pkg_name: []const u8,
    container_name: []const u8,
    function_name: []const u8,
    out: *ZigWriter,
) !void {
    try out.print("test \"$L.$L\" {\n", .{ container_name, function_name });
    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_name});
    try out.print(
        \\const ExpectedFnType = @TypeOf(c.$I);
        \\const ActualFnType = @TypeOf($I.$I.$I);
        \\try std.testing.expect(@typeInfo(ExpectedFnType) == .@"fn");
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
    out: *ZigWriter,
) !void {
    try out.print("test \"$L.$L\" {\n", .{ container_name, function_name });
    try out.print("if (!@hasDecl(c, $S)) return error.SkipZigTest;\n", .{c_name});
    try out.print(
        \\const ExpectedFnType = @TypeOf(c.$I);
        \\const ActualType = $I.$I;
        \\const ActualFnType = @TypeOf(ActualType.$I);
        \\try std.testing.expect(@typeInfo(ExpectedFnType) == .@"fn");
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
