const gstvulkanxcb = @import("gstvulkanxcb");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gstvulkanxcb);
}
