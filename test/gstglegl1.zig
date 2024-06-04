const gstglegl = @import("gstglegl");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstglegl);
}
