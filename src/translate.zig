const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const zig = std.zig;
const Allocator = mem.Allocator;
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
    for (ns.classes) |class| {
        try translateClass(allocator, class, ns, out);
    }
    for (ns.records) |record| {
        try translateRecord(allocator, record, ns, out);
    }
}

fn translateClass(allocator: Allocator, class: gir.Class, ns: gir.Namespace, out: anytype) !void {
    try out.print("pub const {s} = struct {{\n", .{class.name.local});
    for (class.fields) |field| {
        try translateField(allocator, field, ns, out);
    }
    _ = try out.write("};\n\n");
}

fn translateRecord(allocator: Allocator, record: gir.Record, ns: gir.Namespace, out: anytype) !void {
    try out.print("pub const {s} = struct {{\n", .{record.name.local});
    for (record.fields) |field| {
        try translateField(allocator, field, ns, out);
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

const builtins = blk: {
    var buf: [1024]u8 = .{0} ** 1024;
    var map = StringHashMap([]const u8).init(heap.FixedBufferAllocator.init(&buf));
    map.put("gint8", "i8") catch unreachable;
    break :blk map;
};

fn translateType(allocator: Allocator, @"type": gir.Type, ns: gir.Namespace, out: anytype) !void {
    if (@"type".name == null or @"type".c_type == null) {
        _ = try out.write("@compileError(\"type not implemented\"");
        return;
    }

    var c_type = @"type".c_type.?;
    while (true) {
        if (mem.endsWith(u8, c_type, "*")) {
            _ = try out.write("*");
            c_type = c_type[0 .. c_type.len - 1];
        } else if (mem.startsWith(u8, c_type, "const ")) {
            _ = try out.write("const ");
            c_type = c_type[6..c_type.len];
        } else {
            break;
        }
    }

    const name = @"type".name.?;

    // Predefined (built-in) types
    if (name.ns == null) {
        if (builtins.get(name.local)) |builtin| {
            _ = try out.write(builtin);
            return;
        }
    }

    if (name.ns != null and !ascii.eqlIgnoreCase(name.ns.?, ns.name)) {
        const type_ns = try ascii.allocLowerString(allocator, name.ns.?);
        defer allocator.free(type_ns);
        try out.print("{s}.", .{type_ns});
    }
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
    switch (parameter.type) {
        .simple => |simple_type| try translateType(allocator, simple_type, ns, out),
        .array => |array_type| try translateArrayType(allocator, array_type, ns, out),
        .varargs => _ = try out.write("..."),
    }
}
