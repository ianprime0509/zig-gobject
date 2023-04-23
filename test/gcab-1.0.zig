const gcab = @import("gcab");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gcab);
}
