const cudagst = @import("cudagst");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(cudagst);
}
