const pangofc = @import("pangofc");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pangofc);
}
