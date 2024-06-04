const gsk = @import("gsk");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gsk);
}
