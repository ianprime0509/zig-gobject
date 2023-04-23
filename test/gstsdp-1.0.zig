const gstsdp = @import("gstsdp");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstsdp);
}
