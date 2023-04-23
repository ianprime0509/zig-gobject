const webkit = @import("webkit");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(webkit);
}
