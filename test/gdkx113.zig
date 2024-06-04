const gdkx11 = @import("gdkx11");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdkx11);
}
