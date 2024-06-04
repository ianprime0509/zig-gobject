const gstrtp = @import("gstrtp");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstrtp);
}
