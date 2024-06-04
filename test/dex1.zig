const dex = @import("dex");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(dex);
}
