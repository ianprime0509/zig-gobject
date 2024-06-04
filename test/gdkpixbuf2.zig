const gdkpixbuf = @import("gdkpixbuf");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdkpixbuf);
}
