const gstcuda = @import("gstcuda");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstcuda);
}
