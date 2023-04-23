const secret = @import("secret");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(secret);
}
