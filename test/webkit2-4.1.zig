const webkit2 = @import("webkit2");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(webkit2);
}
