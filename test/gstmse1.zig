const gstmse1 = @import("gstmse");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstmse1);
}
