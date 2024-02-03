const gstgl = @import("gstgl");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstgl);
}
