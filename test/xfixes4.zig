const xfixes = @import("xfixes");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(xfixes);
}
