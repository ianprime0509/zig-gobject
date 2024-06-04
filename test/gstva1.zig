const gstva = @import("gstva");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstva);
}
