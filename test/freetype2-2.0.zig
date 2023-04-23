const freetype2 = @import("freetype2");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(freetype2);
}
