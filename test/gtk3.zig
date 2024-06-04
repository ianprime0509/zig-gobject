const gtk = @import("gtk");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gtk);
}
