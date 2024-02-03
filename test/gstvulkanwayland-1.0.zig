const gstvulkanwayland = @import("gstvulkanwayland");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstvulkanwayland);
}
