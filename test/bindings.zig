const std = @import("std");
const refAllDecls = std.testing.refAllDecls;
const ComptimeStringMap = std.ComptimeStringMap;

pub fn refAllBindings(comptime T: type) void {
    @setEvalBranchQuota(100000);

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            if (@TypeOf(@field(T, decl.name)) == type) {
                switch (@typeInfo(@field(T, decl.name))) {
                    .Struct, .Enum, .Union, .Opaque => refAllTypeBindings(@field(T, decl.name)),
                    else => {},
                }
            }
            _ = @field(T, decl.name);
        }
    }
}

const common_decls = [_][]const u8{ "Class", "Iface", "Parent", "Prerequisites" };

const excluded_extra_methods = ComptimeStringMap(void, .{
    .{ "private", {} },
});

fn refAllTypeBindings(comptime T: type) void {
    // We cannot simply reference all declarations in a type, since there are
    // cases where declaration names may overlap, and where declarations may
    // intentionally fail to compile (for example, the `private` method will not
    // compile for types which don't have private data)
    inline for (common_decls) |name| {
        if (@hasDecl(T, name)) {
            _ = @field(T, name);
        }
    }
    if (@hasDecl(T, "Own")) {
        refAllDecls(T.Own);
    }
    if (@hasDecl(T, "OwnMethods")) {
        refAllDecls(T.OwnMethods(T));
    }
    if (@hasDecl(T, "OwnVirtualMethods")) {
        refAllDecls(T.OwnVirtualMethods(typeStruct(T), T));
    }
    if (@hasDecl(T, "Extras")) {
        refAllDecls(T.Extras);
    }
    if (@hasDecl(T, "ExtraMethods")) {
        refAllDeclsExcluding(T.ExtraMethods(T), excluded_extra_methods);
    }
    if (@hasDecl(T, "ExtraVirtualMethods")) {
        refAllDecls(T.ExtraVirtualMethods(typeStruct(T), T));
    }
}

fn refAllDeclsExcluding(comptime T: type, exclusions: anytype) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub and comptime exclusions.get(decl.name) == null) {
            _ = @field(T, decl.name);
        }
    }
}

fn typeStruct(comptime T: type) type {
    if (@hasDecl(T, "Class")) {
        return T.Class;
    } else if (@hasDecl(T, "Iface")) {
        return T.Iface;
    } else {
        @compileError("unable to find type struct for " ++ @typeName(T));
    }
}
