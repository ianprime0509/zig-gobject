const gstplay = @import("gstplay");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstplay);
}
