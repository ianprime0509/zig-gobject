const gudev = @import("gudev");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gudev);
}
