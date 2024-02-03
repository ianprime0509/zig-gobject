const dbusglib = @import("dbusglib");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(dbusglib);
}
