const gstcheck = @import("gstcheck");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstcheck);
}
