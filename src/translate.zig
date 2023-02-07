const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const zig = std.zig;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ArenaAllocator = heap.ArenaAllocator;
const StringHashMap = std.StringHashMap;

const gir = @import("gir.zig");

const Repositories = StringHashMap(gir.Repository);

pub const Error = error{
    InvalidGir,
} || Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn translate(allocator: Allocator, in_dir: fs.Dir, out_dir: fs.Dir, roots: []const []const u8) !void {
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var repos = Repositories.init(allocator);
    for (roots) |root| {
        _ = try translateRepositoryName(a, root, &repos, in_dir, out_dir);
    }
}

fn translateRepositoryName(allocator: Allocator, name: []const u8, repos: *Repositories, in_dir: fs.Dir, out_dir: fs.Dir) !gir.Repository {
    if (repos.get(name)) |repo| {
        return repo;
    }

    const path = try in_dir.realpathAlloc(allocator, name);
    defer allocator.free(path);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const repo = try gir.Repository.parseFile(allocator, path_z);
    try repos.put(try allocator.dupe(u8, name), repo);
    try translateRepository(allocator, repo, repos, in_dir, out_dir);
    return repo;
}

fn translateRepository(allocator: Allocator, repo: gir.Repository, repos: *Repositories, in_dir: fs.Dir, out_dir: fs.Dir) !void {
    for (repo.namespaces) |ns| {
        const file_name = try fileNameAlloc(allocator, ns.name);
        defer allocator.free(file_name);
        const file = try out_dir.createFile(file_name, .{});
        defer file.close();
        var bw = io.bufferedWriter(file.writer());
        const writer = bw.writer();
        var seen = StringHashMap(void).init(allocator);
        defer seen.deinit();
        try translateIncludes(allocator, repo.includes, repos, &seen, in_dir, out_dir, writer);
        _ = try writer.write("\n");
        try translateNamespace(allocator, ns, writer);
        try bw.flush();
        try file.sync();
    }
}

fn translateIncludes(allocator: Allocator, includes: []const gir.Include, repos: *Repositories, seen: *StringHashMap(void), in_dir: fs.Dir, out_dir: fs.Dir, out: anytype) Error!void {
    for (includes) |include| {
        const include_source = try fmt.allocPrint(allocator, "{s}-{s}.gir", .{ include.name, include.version });
        defer allocator.free(include_source);
        if (seen.contains(include_source)) {
            return;
        }
        const include_file_name = try fileNameAlloc(allocator, include.name);
        defer allocator.free(include_file_name);
        const include_ns = try ascii.allocLowerString(allocator, include.name);
        defer allocator.free(include_ns);
        try out.print("const {s} = @import(\"{s}\");\n", .{ include_ns, include_file_name });
        const include_repo = try translateRepositoryName(allocator, include_source, repos, in_dir, out_dir);
        try translateIncludes(allocator, include_repo.includes, repos, seen, in_dir, out_dir, out);
        try seen.put(try allocator.dupe(u8, include_source), {});
    }
}

fn fileNameAlloc(allocator: Allocator, name: []const u8) ![]u8 {
    const file_name = try fmt.allocPrint(allocator, "{s}.zig", .{name});
    _ = ascii.lowerString(file_name, file_name);
    return file_name;
}

fn translateNamespace(allocator: Allocator, ns: gir.Namespace, out: anytype) !void {
    for (ns.aliases) |alias| {
        try translateAlias(allocator, alias, ns, out);
    }
    for (ns.classes) |class| {
        try translateClass(allocator, class, ns, out);
    }
    for (ns.records) |record| {
        try translateRecord(allocator, record, ns, out);
    }
    for (ns.functions) |function| {
        try translateFunction(allocator, function, ns, "", out);
    }
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, ns: gir.Namespace, out: anytype) !void {
    try out.print("pub const {s} = ", .{alias.name});
    try translateType(allocator, alias.type, ns, out);
    _ = try out.write(";\n\n");
}

fn translateClass(allocator: Allocator, class: gir.Class, ns: gir.Namespace, out: anytype) !void {
    try out.print("pub const {s} = struct {{\n", .{class.name});
    try out.print("    const Self = {s};\n\n", .{class.name});
    for (class.fields) |field| {
        try translateField(allocator, field, ns, out);
    }
    if (class.fields.len > 0) {
        _ = try out.write("\n");
    }
    for (class.functions) |function| {
        try translateFunction(allocator, function, ns, " " ** 4, out);
    }
    if (class.functions.len > 0) {
        _ = try out.write("\n");
    }
    for (class.constructors) |constructor| {
        try translateConstructor(allocator, constructor, ns, " " ** 4, out);
    }
    if (class.constructors.len > 0) {
        _ = try out.write("\n");
    }
    if (class.methods.len > 0) {
        try out.print("    pub usingnamespace {s}Methods(Self);\n", .{class.name});
    }
    _ = try out.write("};\n\n");

    if (class.methods.len > 0) {
        try out.print("pub fn {s}Methods(comptime Self: type) type {{\n", .{class.name});
        _ = try out.write("    return opaque{\n");
        for (class.methods) |method| {
            try translateMethod(allocator, method, ns, " " ** 8, out);
        }
        if (class.parent) |parent| {
            _ = try out.write("        pub usingnamespace ");
            try translateNameNs(allocator, parent.ns, ns, out);
            try out.print("{s}Methods(Self);\n", .{parent.local});
        }
        _ = try out.write("    };\n");
        _ = try out.write("}\n\n");
    }
}

fn translateRecord(allocator: Allocator, record: gir.Record, ns: gir.Namespace, out: anytype) !void {
    try out.print("pub const {s} = struct {{\n", .{record.name});
    try out.print("    const Self = {s};\n\n", .{record.name});
    for (record.fields) |field| {
        try translateField(allocator, field, ns, out);
    }
    if (record.fields.len > 0) {
        _ = try out.write("\n");
    }
    for (record.functions) |function| {
        try translateFunction(allocator, function, ns, " " ** 4, out);
    }
    if (record.functions.len > 0) {
        _ = try out.write("\n");
    }
    for (record.constructors) |constructor| {
        try translateConstructor(allocator, constructor, ns, " " ** 4, out);
    }
    if (record.constructors.len > 0) {
        _ = try out.write("\n");
    }
    for (record.methods) |method| {
        try translateMethod(allocator, method, ns, " " ** 4, out);
    }
    _ = try out.write("};\n\n");
}

fn translateField(allocator: Allocator, field: gir.Field, ns: gir.Namespace, out: anytype) !void {
    try out.print("    {}: ", .{zig.fmtId(field.name)});
    try translateFieldType(allocator, field.type, ns, out);
    _ = try out.write(",\n");
}

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, ns: gir.Namespace, out: anytype) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
        .callback => |callback| try translateCallback(allocator, callback, ns, out),
    }
}

fn translateFunction(allocator: Allocator, function: gir.Function, ns: gir.Namespace, indent: []const u8, out: anytype) !void {
    // extern declaration
    try out.print("{s}extern fn {s}(", .{ indent, zig.fmtId(function.c_identifier) });

    var i: usize = 0;
    while (i < function.parameters.len) : (i += 1) {
        try translateParameter(allocator, function.parameters[i], ns, out);
        if (i < function.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write(") callconv(.C) ");
    switch (function.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
    }
    _ = try out.write(";\n\n");

    // function wrapper
    var fnName = try toCamelCase(allocator, function.name);
    defer allocator.free(fnName);
    try out.print("{s}pub fn {s}(", .{ indent, zig.fmtId(fnName) });

    i = 0;
    while (i < function.parameters.len) : (i += 1) {
        try translateParameter(allocator, function.parameters[i], ns, out);
        if (i < function.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write(") ");
    switch (function.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
    }
    _ = try out.print(" {{\n{s}    {s}(", .{ indent, zig.fmtId(function.c_identifier) });
    i = 0;
    while (i < function.parameters.len) : (i += 1) {
        try out.print("{s}", .{zig.fmtId(function.parameters[i].name)});
        if (i < function.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.print(");\n{s}}}\n\n", .{indent});
}

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, ns: gir.Namespace, indent: []const u8, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = constructor.name,
        .c_identifier = constructor.c_identifier,
        .parameters = constructor.parameters,
        .return_value = constructor.return_value,
    }, ns, indent, out);
}

fn translateMethod(allocator: Allocator, method: gir.Method, ns: gir.Namespace, indent: []const u8, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = method.name,
        .c_identifier = method.c_identifier,
        .parameters = method.parameters,
        .return_value = method.return_value,
    }, ns, indent, out);
}

const builtins = std.ComptimeStringMap([]const u8, .{
    .{ "gboolean", "bool" },
    .{ "gchar", "u8" },
    .{ "guchar", "u8" },
    .{ "gint8", "i8" },
    .{ "guint8", "u8" },
    .{ "gint16", "i16" },
    .{ "guint16", "u16" },
    .{ "gint32", "i32" },
    .{ "guint32", "u32" },
    .{ "gint64", "i64" },
    .{ "guint64", "u64" },
    .{ "gshort", "c_short" },
    .{ "gushort", "c_ushort" },
    .{ "gint", "c_int" },
    .{ "guint", "c_uint" },
    .{ "glong", "c_long" },
    .{ "gulong", "c_ulong" },
    .{ "gsize", "usize" },
    .{ "gssize", "isize" },
    .{ "gpointer", "*anyopaque" },
    .{ "gconstpointer", "*const anyopaque" },
    .{ "long double", "c_longdouble" },
    .{ "va_list", "@compileError(\"va_list not supported\")" },
    .{ "none", "void" },
});

fn translateType(allocator: Allocator, @"type": gir.Type, ns: gir.Namespace, out: anytype) !void {
    if (@"type".name == null or @"type".c_type == null) {
        _ = try out.write("@compileError(\"type not implemented\")");
        return;
    }

    var name = @"type".name.?;
    var c_type = @"type".c_type.?;

    // Special case for GType, which seems to have an inconsistent namespace
    if (mem.eql(u8, name.local, "GType")) {
        name = .{ .ns = "gobject", .local = "Type" };
    }

    // Special cases for string types
    if (name.ns == null and (mem.eql(u8, name.local, "utf8") or mem.eql(u8, name.local, "filename"))) {
        name = .{ .ns = null, .local = "gchar" };
        if (mem.endsWith(u8, c_type, "*")) {
            _ = try out.write("[*:0]");
            c_type = c_type[0 .. c_type.len - 1];
        }
    }

    // There are a few cases where "const" is used to qualify a non-pointer
    // type, which is irrelevant to translation and will result in invalid types if
    // not handled (e.g. const c_int)
    var pointer = false;
    while (true) {
        if (mem.endsWith(u8, c_type, "*")) {
            pointer = true;
            _ = try out.write("*");
            c_type = c_type[0 .. c_type.len - 1];
        } else if (mem.startsWith(u8, c_type, "const ")) {
            if (pointer) {
                _ = try out.write("const ");
            }
            c_type = c_type[6..c_type.len];
        } else {
            break;
        }
    }

    // Predefined (built-in) types
    if (name.ns == null) {
        if (builtins.get(name.local)) |builtin| {
            _ = try out.write(builtin);
            return;
        }
    }

    try translateNameNs(allocator, name.ns, ns, out);
    _ = try out.write(name.local);
}

fn translateArrayType(allocator: Allocator, @"type": gir.ArrayType, ns: gir.Namespace, out: anytype) !void {
    if (@"type".fixed_size) |fixed_size| {
        try out.print("[{}]", .{fixed_size});
    } else {
        _ = try out.write("[*]");
    }
    switch (@"type".element.*) {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
    }
}

fn translateCallback(allocator: Allocator, callback: gir.Callback, ns: gir.Namespace, out: anytype) !void {
    _ = try out.write("*const fn (");
    var i: usize = 0;
    while (i < callback.parameters.len) : (i += 1) {
        try translateParameter(allocator, callback.parameters[i], ns, out);
        if (i < callback.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write(") ");
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
    }
}

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, ns: gir.Namespace, out: anytype) !void {
    try out.print("{}: ", .{zig.fmtId(parameter.name)});
    if (parameter.instance) {
        // TODO: what if the instance parameter isn't a pointer?
        if (mem.startsWith(u8, parameter.type.simple.c_type.?, "const ")) {
            _ = try out.write("*const Self");
        } else {
            _ = try out.write("*Self");
        }
    } else {
        switch (parameter.type) {
            .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
            .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
            .varargs => _ = try out.write("@compileError(\"varargs not implemented\")"),
        }
    }
}

fn translateNameNs(allocator: Allocator, nameNs: ?[]const u8, ns: gir.Namespace, out: anytype) !void {
    if (nameNs != null and !ascii.eqlIgnoreCase(nameNs.?, ns.name)) {
        const type_ns = try ascii.allocLowerString(allocator, nameNs.?);
        defer allocator.free(type_ns);
        try out.print("{s}.", .{type_ns});
    }
}

fn toCamelCase(allocator: Allocator, name: []const u8) ![]u8 {
    var out = ArrayList(u8).init(allocator);
    var words = mem.split(u8, name, "_");
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
