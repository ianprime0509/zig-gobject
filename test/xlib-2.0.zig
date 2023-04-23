const xlib = @import("xlib");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(xlib);
}
