const gstvulkan = @import("gstvulkan");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstvulkan);
}
