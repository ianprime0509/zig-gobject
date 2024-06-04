const gst = @import("gst");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gst);
}
