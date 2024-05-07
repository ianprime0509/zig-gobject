const giounix = @import("giounix");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(giounix);
}
