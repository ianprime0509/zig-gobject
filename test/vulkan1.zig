const vulkan = @import("vulkan");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(vulkan);
}
