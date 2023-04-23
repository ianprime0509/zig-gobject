const gdkwayland = @import("gdkwayland");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdkwayland);
}
