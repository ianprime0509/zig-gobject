const gee = @import("gee");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gee);
}
