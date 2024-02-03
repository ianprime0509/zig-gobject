const gstnet = @import("gstnet");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstnet);
}
