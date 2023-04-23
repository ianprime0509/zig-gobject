const gstcontroller = @import("gstcontroller");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstcontroller);
}
