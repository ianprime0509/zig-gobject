const manette = @import("manette");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(manette);
}
