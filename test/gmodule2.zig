const gmodule = @import("gmodule");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gmodule);
}
