const gstpbutils = @import("gstpbutils");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstpbutils);
}
