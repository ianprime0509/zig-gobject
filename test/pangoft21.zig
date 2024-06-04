const pangoft2 = @import("pangoft2");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pangoft2);
}
