const gtksource = @import("gtksource");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gtksource);
}
