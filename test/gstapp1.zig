const gstapp = @import("gstapp");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstapp);
}
