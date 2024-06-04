const libproxy = @import("libproxy");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(libproxy);
}
