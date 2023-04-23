const rsvg = @import("rsvg");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(rsvg);
}
