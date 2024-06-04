const gdkpixdata = @import("gdkpixdata");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdkpixdata);
}
