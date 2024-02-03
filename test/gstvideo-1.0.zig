const gstvideo = @import("gstvideo");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstvideo);
}
