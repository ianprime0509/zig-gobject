const gstaudio = @import("gstaudio");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstaudio);
}
