const gstinsertbin = @import("gstinsertbin");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstinsertbin);
}
