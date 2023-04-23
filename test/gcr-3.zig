const gcr = @import("gcr");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gcr);
}
