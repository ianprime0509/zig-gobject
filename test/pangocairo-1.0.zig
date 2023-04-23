const pangocairo = @import("pangocairo");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pangocairo);
}
