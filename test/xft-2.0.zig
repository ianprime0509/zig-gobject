const xft = @import("xft");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(xft);
}
