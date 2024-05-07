const girepository = @import("girepository");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(girepository);
}
