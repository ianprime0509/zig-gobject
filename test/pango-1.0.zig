const pango = @import("pango");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pango);
}
