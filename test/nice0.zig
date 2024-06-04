const nice = @import("nice");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(nice);
}
