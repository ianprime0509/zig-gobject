const ibus = @import("ibus");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(ibus);
}
