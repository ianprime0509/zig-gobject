const glib = @import("glib");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(glib);
}
