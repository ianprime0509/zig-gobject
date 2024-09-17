const std = @import("std");
const compat = @import("abi/compat.zig");

pub fn refAllBindings(comptime T: type) void {
    @setEvalBranchQuota(100000);

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (compat.typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => std.testing.refAllDecls(@field(T, decl.name)),
                else => {},
            }
        }
        _ = @field(T, decl.name);
    }
}
