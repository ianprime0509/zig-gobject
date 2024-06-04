const gstrtsp = @import("gstrtsp");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstrtsp);
}
