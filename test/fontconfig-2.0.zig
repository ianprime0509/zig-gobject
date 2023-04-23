const fontconfig = @import("fontconfig");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(fontconfig);
}
