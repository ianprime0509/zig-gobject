const webkitwebprocessextension = @import("webkitwebprocessextension");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(webkitwebprocessextension);
}
