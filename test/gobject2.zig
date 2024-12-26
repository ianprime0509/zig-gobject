const gobject = @import("gobject");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gobject);
}
