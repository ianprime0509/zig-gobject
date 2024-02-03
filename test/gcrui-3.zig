const gcrui = @import("gcrui");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gcrui);
}
