const gstglwayland = @import("gstglwayland");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstglwayland);
}
