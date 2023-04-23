const gck = @import("gck");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gck);
}
