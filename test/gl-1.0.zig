const gl = @import("gl");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gl);
}
