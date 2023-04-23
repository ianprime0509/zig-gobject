const atk = @import("atk");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(atk);
}
