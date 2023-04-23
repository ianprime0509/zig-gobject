const gstglx11 = @import("gstglx11");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstglx11);
}
