const handy = @import("handy");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(handy);
}
