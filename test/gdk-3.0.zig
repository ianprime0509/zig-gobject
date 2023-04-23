const gdk = @import("gdk");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdk);
}
