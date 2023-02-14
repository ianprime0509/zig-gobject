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

const extras = @import("extras.zig");
const gir = @import("gir.zig");

const Repositories = StringHashMap(gir.Repository);

pub const Error = error{
    InvalidGir,
    InvalidExtras,
} || Allocator.Error || fs.File.OpenError || fs.File.WriteError || error{
    FileSystem,
    NotSupported,
};

pub fn translate(allocator: Allocator, in_dir: fs.Dir, extras_dir: fs.Dir, out_dir: fs.Dir, roots: []const []const u8) !void {
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var repos = Repositories.init(allocator);
    for (roots) |root| {
        _ = try translateRepositoryName(a, root, &repos, in_dir, extras_dir, out_dir);
    }
}

fn translateRepositoryName(allocator: Allocator, name: []const u8, repos: *Repositories, in_dir: fs.Dir, extras_dir: fs.Dir, out_dir: fs.Dir) !gir.Repository {
    if (repos.get(name)) |repo| {
        return repo;
    }

    const repo = blk: {
        const path = try realpathAllocZ(allocator, in_dir, name);
        defer allocator.free(path);
        break :blk try gir.Repository.parseFile(allocator, path);
    };

    const extras_repo = blk: {
        const extras_name = try fmt.allocPrint(allocator, "{s}.extras", .{name});
        defer allocator.free(extras_name);
        const path = realpathAllocZ(allocator, extras_dir, extras_name) catch |err| switch (err) {
            error.FileNotFound => break :blk null,
            else => return err,
        };
        defer allocator.free(path);
        break :blk try extras.Repository.parseFile(allocator, path);
    };

    try repos.put(try allocator.dupe(u8, name), repo);

    try translateRepository(allocator, repo, extras_repo, repos, in_dir, extras_dir, out_dir);
    return repo;
}

fn realpathAllocZ(allocator: Allocator, dir: fs.Dir, name: []const u8) ![:0]u8 {
    const path = try dir.realpathAlloc(allocator, name);
    defer allocator.free(path);
    return try allocator.dupeZ(u8, path);
}

fn translateRepository(allocator: Allocator, repo: gir.Repository, maybe_extras_repo: ?extras.Repository, repos: *Repositories, in_dir: fs.Dir, extras_dir: fs.Dir, out_dir: fs.Dir) !void {
    for (repo.namespaces) |ns| {
        const file_name = try fileNameAlloc(allocator, ns.name);
        defer allocator.free(file_name);
        const file = try out_dir.createFile(file_name, .{});
        defer file.close();
        var bw = io.bufferedWriter(file.writer());
        const out = bw.writer();
        var seen = StringHashMap(void).init(allocator);
        defer seen.deinit();
        try translateIncludes(allocator, repo.includes, repos, &seen, in_dir, extras_dir, out_dir, out);
        // Special case: GLib references GObject despite not including it
        if (mem.eql(u8, ns.name, "GLib")) {
            _ = try out.write("const gobject = @import(\"gobject.zig\");\n");
        }
        // Having the current namespace in scope using the same name makes type
        // translation logic simpler (no need to know what namespace we're in)
        var ns_lower = try ascii.allocLowerString(allocator, ns.name);
        defer allocator.free(ns_lower);
        try out.print("const {s} = @This();\n\n", .{ns_lower});

        const extras_ns = blk: {
            if (maybe_extras_repo) |extras_repo| {
                for (extras_repo.namespaces) |extras_ns| {
                    if (mem.eql(u8, ns.name, extras_ns.name) and mem.eql(u8, ns.version, extras_ns.version)) {
                        break :blk extras_ns;
                    }
                }
            }
            break :blk null;
        };

        try translateNamespace(allocator, ns, extras_ns, out);

        try bw.flush();
        try file.sync();
    }
}

fn translateIncludes(allocator: Allocator, includes: []const gir.Include, repos: *Repositories, seen: *StringHashMap(void), in_dir: fs.Dir, extras_dir: fs.Dir, out_dir: fs.Dir, out: anytype) Error!void {
    for (includes) |include| {
        const include_source = try fmt.allocPrint(allocator, "{s}-{s}.gir", .{ include.name, include.version });
        defer allocator.free(include_source);
        if (seen.contains(include_source)) {
            continue;
        }
        const include_file_name = try fileNameAlloc(allocator, include.name);
        defer allocator.free(include_file_name);
        const include_ns = try ascii.allocLowerString(allocator, include.name);
        defer allocator.free(include_ns);
        try out.print("const {s} = @import(\"{s}\");\n", .{ include_ns, include_file_name });
        const include_repo = try translateRepositoryName(allocator, include_source, repos, in_dir, extras_dir, out_dir);
        try translateIncludes(allocator, include_repo.includes, repos, seen, in_dir, extras_dir, out_dir, out);
        try seen.put(try allocator.dupe(u8, include_source), {});
    }
}

fn fileNameAlloc(allocator: Allocator, name: []const u8) ![]u8 {
    const file_name = try fmt.allocPrint(allocator, "{s}.zig", .{name});
    _ = ascii.lowerString(file_name, file_name);
    return file_name;
}

fn translateNamespace(allocator: Allocator, ns: gir.Namespace, maybe_extras_ns: ?extras.Namespace, out: anytype) !void {
    for (ns.aliases) |alias| {
        try translateAlias(allocator, alias, out);
    }
    for (ns.classes) |class| {
        try translateClass(allocator, class, out);
    }
    for (ns.interfaces) |interface| {
        try translateInterface(allocator, interface, out);
    }
    for (ns.records) |record| {
        try translateRecord(allocator, record, out);
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

    if (maybe_extras_ns) |extras_ns| {
        for (extras_ns.functions) |function| {
            try translateExtraFunction(function, "", out);
        }
    }
}

fn translateAlias(allocator: Allocator, alias: gir.Alias, out: anytype) !void {
    try out.print("pub const {s} = ", .{alias.name});
    try translateType(allocator, alias.type, out);
    _ = try out.write(";\n\n");
}

fn translateClass(allocator: Allocator, class: gir.Class, out: anytype) !void {
    // class type
    try out.print("pub const {s} = extern struct {{\n", .{class.name});
    try out.print("    const Self = {s};\n\n", .{class.name});
    for (class.fields) |field| {
        try translateField(allocator, field, out);
    }
    if (class.fields.len > 0) {
        _ = try out.write("\n");
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
    try out.print("    pub usingnamespace {s}Methods(Self);\n", .{class.name});
    _ = try out.write("};\n\n");

    // methods mixin
    try out.print("pub fn {s}Methods(comptime Self: type) type {{\n", .{class.name});
    if (class.methods.len == 0 and class.signals.len == 0 and class.parent == null) {
        _ = try out.write("_ = Self;\n");
    }
    _ = try out.write("    return opaque{\n");
    for (class.methods) |method| {
        try translateMethod(allocator, method, " " ** 8, out);
    }
    for (class.signals) |signal| {
        try translateSignal(allocator, signal, " " ** 8, out);
    }
    if (class.parent) |parent| {
        try out.print("        pub fn as{s}(p_self: *Self) *", .{parent.local});
        try translateNameNs(allocator, parent.ns, out);
        try out.print("{s} {{\n", .{parent.local});
        _ = try out.write("            return @ptrCast(*");
        try translateNameNs(allocator, parent.ns, out);
        try out.print("{s}, p_self);\n", .{parent.local});
        _ = try out.write("        }\n\n");

        _ = try out.write("        pub usingnamespace ");
        try translateNameNs(allocator, parent.ns, out);
        try out.print("{s}Methods(Self);\n", .{parent.local});
    }
    _ = try out.write("    };\n");
    _ = try out.write("}\n\n");
}

fn translateInterface(allocator: Allocator, interface: gir.Interface, out: anytype) !void {
    // interface type
    try out.print("pub const {s} = opaque {{\n", .{interface.name});
    try out.print("    const Self = {s};\n\n", .{interface.name});
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
    try out.print("    pub usingnamespace {s}Methods(Self);\n", .{interface.name});
    _ = try out.write("};\n\n");

    // methods mixin
    try out.print("pub fn {s}Methods(comptime Self: type) type {{\n", .{interface.name});
    if (interface.methods.len == 0 and interface.signals.len == 0) {
        _ = try out.write("_ = Self;\n");
    }
    _ = try out.write("    return opaque{\n");
    for (interface.methods) |method| {
        try translateMethod(allocator, method, " " ** 8, out);
    }
    for (interface.signals) |signal| {
        try translateSignal(allocator, signal, " " ** 8, out);
    }
    _ = try out.write("    };\n");
    _ = try out.write("}\n\n");
}

fn translateRecord(allocator: Allocator, record: gir.Record, out: anytype) !void {
    try out.print("pub const {s} = extern struct {{\n", .{record.name});
    try out.print("    const Self = {s};\n\n", .{record.name});
    for (record.fields) |field| {
        try translateField(allocator, field, out);
    }
    if (record.fields.len > 0) {
        _ = try out.write("\n");
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
    for (record.methods) |method| {
        try translateMethod(allocator, method, " " ** 4, out);
    }
    _ = try out.write("};\n\n");
}

fn translateUnion(allocator: Allocator, @"union": gir.Union, out: anytype) !void {
    try out.print("pub const {s} = extern union {{\n", .{@"union".name});
    try out.print("    const Self = {s};\n\n", .{@"union".name});
    for (@"union".fields) |field| {
        try translateField(allocator, field, out);
    }
    if (@"union".fields.len > 0) {
        _ = try out.write("\n");
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
    try out.print("    {}: ", .{zig.fmtId(field.name)});
    try translateFieldType(allocator, field.type, out);
    _ = try out.write(",\n");
}

fn translateFieldType(allocator: Allocator, @"type": gir.FieldType, out: anytype) !void {
    switch (@"type") {
        .simple => |simple_type| try translateType(allocator, simple_type, out),
        .array => |array_type| try translateArrayType(allocator, array_type, out),
        .callback => |callback| try translateCallback(allocator, callback, false, out),
    }
}

fn translateBitField(allocator: Allocator, bit_field: gir.BitField, out: anytype) !void {
    var needsI64 = false;
    for (bit_field.members) |member| {
        if (member.value >= 1 << 31) {
            needsI64 = true;
        }
    }

    const tagType = if (needsI64) "i64" else "i32";
    var paddingNeeded: usize = if (needsI64) 64 else 32;
    try out.print("pub const {s} = packed struct({s}) {{\n", .{ bit_field.name, tagType });
    for (bit_field.members) |member| {
        if (member.value > 0) {
            try out.print("    {s}: bool = false,\n", .{zig.fmtId(member.name)});
            paddingNeeded -= 1;
        }
    }
    if (paddingNeeded > 0) {
        try out.print("    _padding: u{} = 0,\n", .{paddingNeeded});
    }

    try out.print("\n    const Self = {s};\n", .{bit_field.name});

    if (bit_field.functions.len > 0) {
        _ = try out.write("\n");
        for (bit_field.functions) |function| {
            try translateFunction(allocator, function, " " ** 8, out);
        }
    }

    _ = try out.write("};\n\n");
}

fn translateEnum(allocator: Allocator, @"enum": gir.Enum, out: anytype) !void {
    var needsI64 = false;
    for (@"enum".members) |member| {
        if (member.value >= 1 << 31) {
            needsI64 = true;
        }
    }

    const tagType = if (needsI64) "i64" else "i32";
    try out.print("pub const {s} = enum({s}) {{\n", .{ @"enum".name, tagType });
    for (@"enum".members) |member| {
        try out.print("    {s} = {},\n", .{ zig.fmtId(member.name), member.value });
    }

    try out.print("\n    const Self = {s};\n", .{@"enum".name});

    if (@"enum".functions.len > 0) {
        _ = try out.write("\n");
        for (@"enum".functions) |function| {
            try translateFunction(allocator, function, " " ** 8, out);
        }
    }

    _ = try out.write("};\n\n");
}

fn translateFunction(allocator: Allocator, function: gir.Function, indent: []const u8, out: anytype) !void {
    if (function.moved_to != null) {
        return;
    }

    // extern declaration
    try out.print("{s}extern fn {s}(", .{ indent, zig.fmtId(function.c_identifier) });

    var i: usize = 0;
    while (i < function.parameters.len) : (i += 1) {
        try translateParameter(allocator, function.parameters[i], out);
        if (i < function.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write(") callconv(.C) ");
    try translateReturnValue(allocator, function.return_value, out);
    _ = try out.write(";\n\n");

    // function rename
    var fnName = try toCamelCase(allocator, function.name, "_");
    defer allocator.free(fnName);
    try out.print("{s}pub const {s} = {s};\n\n", .{ indent, zig.fmtId(fnName), zig.fmtId(function.c_identifier) });
}

fn translateConstructor(allocator: Allocator, constructor: gir.Constructor, indent: []const u8, out: anytype) !void {
    // TODO: reduce duplication with translateFunction; we need to override the
    // return type here due to many GTK constructors returning just "Widget"
    // instead of their actual type
    if (constructor.moved_to != null) {
        return;
    }

    // extern declaration
    try out.print("{s}extern fn {s}(", .{ indent, zig.fmtId(constructor.c_identifier) });

    var i: usize = 0;
    while (i < constructor.parameters.len) : (i += 1) {
        try translateParameter(allocator, constructor.parameters[i], out);
        if (i < constructor.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    // TODO: consider if the return value is const, or maybe not even a pointer at all
    _ = try out.write(") callconv(.C) *Self;\n\n");

    // constructor rename
    var fnName = try toCamelCase(allocator, constructor.name, "_");
    defer allocator.free(fnName);
    try out.print("{s}pub const {s} = {s};\n\n", .{ indent, zig.fmtId(fnName), zig.fmtId(constructor.c_identifier) });
}

fn translateMethod(allocator: Allocator, method: gir.Method, indent: []const u8, out: anytype) !void {
    try translateFunction(allocator, .{
        .name = method.name,
        .c_identifier = method.c_identifier,
        .moved_to = method.moved_to,
        .parameters = method.parameters,
        .return_value = method.return_value,
    }, indent, out);
}

fn translateSignal(allocator: Allocator, signal: gir.Signal, indent: []const u8, out: anytype) !void {
    var upper_signal_name = try toCamelCase(allocator, signal.name, "-");
    defer allocator.free(upper_signal_name);
    if (upper_signal_name.len > 0) {
        upper_signal_name[0] = ascii.toUpper(upper_signal_name[0]);
    }

    // normal connection
    try out.print("{s}pub fn connect{s}(p_self: *Self, comptime T: type, p_callback: ", .{ indent, upper_signal_name });
    // TODO: verify that T is a pointer type or compatible
    try translateSignalCallbackType(allocator, signal, out);
    _ = try out.write(", p_data: T) c_ulong {\n");

    try out.print("{s}    return ", .{indent});
    try translateNameNs(allocator, "gobject", out);
    try out.print("signalConnectData(p_self, \"{}\", @ptrCast(", .{zig.fmtEscapes(signal.name)});
    try translateNameNs(allocator, "gobject", out);
    _ = try out.write("Callback, p_callback), p_data, null, .{});\n");

    try out.print("{s}}}\n\n", .{indent});
}

fn translateSignalCallbackType(allocator: Allocator, signal: gir.Signal, out: anytype) !void {
    _ = try out.write("*const fn (*Self, ");
    for (signal.parameters) |parameter| {
        try translateParameter(allocator, parameter, out);
        _ = try out.write(", ");
    }
    _ = try out.write("T) callconv(.C) ");
    try translateReturnValue(allocator, signal.return_value, out);
}

fn translateConstant(allocator: Allocator, constant: gir.Constant, indent: []const u8, out: anytype) !void {
    // TODO: it would be more idiomatic to use lowercase constant names, but
    // there are way too many constant pairs which differ only in case, especially
    // the names of keyboard keys (e.g. KEY_A and KEY_a in GDK). There is
    // probably some heuristic we can use to at least lowercase most of them.
    try out.print("{s}pub const {s}: ", .{ indent, zig.fmtId(constant.name) });
    try translateAnyType(allocator, constant.type, out);
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
    .{ "gunichar2", "u16" },
    .{ "gunichar", "u32" },
    .{ "gfloat", "f32" },
    .{ "gdouble", "f64" },
    .{ "long double", "c_longdouble" },
    .{ "gpointer", "?*anyopaque" },
    .{ "gconstpointer", "?*const anyopaque" },
    .{ "va_list", "@compileError(\"va_list not supported\")" },
    .{ "none", "void" },
});

fn translateAnyType(allocator: Allocator, @"type": gir.AnyType, out: anytype) !void {
    switch (@"type") {
        .simple => |simple| try translateType(allocator, simple, out),
        .array => |array| try translateArrayType(allocator, array, out),
    }
}

fn translateType(allocator: Allocator, @"type": gir.Type, out: anytype) !void {
    if (@"type".name == null) {
        _ = try out.write("@compileError(\"type not implemented\")");
        return;
    }

    var name = @"type".name.?;
    var c_type = @"type".c_type orelse "";

    // Special cases for namespaced types
    if (mem.eql(u8, name.local, "GType")) {
        name = .{ .ns = "gobject", .local = "Type" };
    }

    // Special case for type-erased pointers
    if (mem.eql(u8, c_type, "gpointer")) {
        _ = try out.write("?*anyopaque");
        return;
    } else if (mem.eql(u8, c_type, "gconstpointer")) {
        _ = try out.write("?*const anyopaque");
        return;
    }

    // There are a few cases where "const" is used to qualify a non-pointer
    // type, which is irrelevant to translation and will result in invalid types if
    // not handled (e.g. const c_int)
    var pointer = false;

    // Special cases for string types
    if (name.ns == null and (mem.eql(u8, name.local, "utf8") or mem.eql(u8, name.local, "filename"))) {
        name = .{ .ns = null, .local = "gchar" };
        if (c_type.len == 0) {
            c_type = "char*";
        }
        if (mem.endsWith(u8, c_type, "*")) {
            pointer = true;
            _ = try out.write("[*:0]");
            c_type = c_type[0 .. c_type.len - 1];
        }
    }

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

    try translateNameNs(allocator, name.ns, out);
    _ = try out.write(name.local);
}

fn translateArrayType(allocator: Allocator, @"type": gir.ArrayType, out: anytype) !void {
    if (@"type".fixed_size) |fixed_size| {
        try out.print("[{}]", .{fixed_size});
    } else {
        _ = try out.write("[*]");
    }
    switch (@"type".element.*) {
        .simple => |simple_type| try translateType(allocator, simple_type, out),
        .array => |array_type| try translateArrayType(allocator, array_type, out),
    }
}

fn translateCallback(allocator: Allocator, callback: gir.Callback, named: bool, out: anytype) !void {
    // TODO: workaround specific to ClosureNotify until https://github.com/ziglang/zig/issues/12325 is fixed
    if (named and mem.eql(u8, callback.name, "ClosureNotify")) {
        _ = try out.write("pub const ClosureNotify = ?*const fn (p_data: ?*anyopaque, p_closure: *anyopaque) callconv(.C) void;\n\n");
        return;
    }

    if (named) {
        try out.print("pub const {s} = ", .{callback.name});
    }

    _ = try out.write("?*const fn (");
    var i: usize = 0;
    while (i < callback.parameters.len) : (i += 1) {
        try translateParameter(allocator, callback.parameters[i], out);
        if (i < callback.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    _ = try out.write(") callconv(.C) ");
    switch (callback.return_value.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, out),
        .array => |array_type| try translateArrayType(allocator, array_type, out),
    }

    if (named) {
        _ = try out.write(";\n\n");
    }
}

fn translateParameter(allocator: Allocator, parameter: gir.Parameter, out: anytype) !void {
    try translateParameterName(allocator, parameter.name, out);
    _ = try out.write(": ");
    if (parameter.instance) {
        // TODO: what if the instance parameter isn't a pointer?
        if (mem.startsWith(u8, parameter.type.simple.c_type.?, "const ")) {
            _ = try out.write("*const Self");
        } else {
            _ = try out.write("*Self");
        }
    } else {
        switch (parameter.type) {
            .simple => |simple_type| try translateType(allocator, simple_type, out),
            .array => |array_type| try translateArrayType(allocator, array_type, out),
            .varargs => _ = try out.write("@compileError(\"varargs not implemented\")"),
        }
    }
}

fn translateParameterName(allocator: Allocator, parameterName: []const u8, out: anytype) !void {
    var translatedName = try fmt.allocPrint(allocator, "p_{s}", .{parameterName});
    defer allocator.free(translatedName);
    try out.print("{s}", .{zig.fmtId(translatedName)});
}

fn translateReturnValue(allocator: Allocator, return_value: gir.ReturnValue, out: anytype) !void {
    if (return_value.nullable) {
        _ = try out.write("?");
    }
    try translateAnyType(allocator, return_value.type, out);
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
    try out.print("{s}pub fn {}(", .{ indent, zig.fmtId(function.name) });
    var i: usize = 0;
    while (i < function.parameters.len) : (i += 1) {
        const parameter = function.parameters[i];
        try out.print("{}: {s}", .{ zig.fmtId(parameter.name), parameter.type });
        if (i < function.parameters.len - 1) {
            _ = try out.write(", ");
        }
    }
    try out.print(") {s} {{\n", .{function.return_value.type});

    var lines = mem.split(u8, function.body, "\n");
    while (lines.next()) |line| {
        try out.print("{s}    {s}\n", .{ indent, line });
    }

    try out.print("{s}}}\n\n", .{indent});
}
