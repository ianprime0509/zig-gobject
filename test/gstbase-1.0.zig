const gstbase = @import("gstbase");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstbase);
}
