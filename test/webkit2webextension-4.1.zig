const webkit2webextension = @import("webkit2webextension");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(webkit2webextension);
}
