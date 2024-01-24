const std = @import("std");

pub fn refAllBindings(comptime T: type) void {
    @setEvalBranchQuota(100000);

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .Struct, .Enum, .Union, .Opaque => std.testing.refAllDecls(@field(T, decl.name)),
                else => {},
            }
        }
        _ = @field(T, decl.name);
    }
}
