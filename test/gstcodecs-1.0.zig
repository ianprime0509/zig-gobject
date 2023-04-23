const gstcodecs = @import("gstcodecs");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstcodecs);
}
