const gdkwin32 = @import("gdkwin32");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdkwin32);
}
