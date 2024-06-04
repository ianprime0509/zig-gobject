const glibunix = @import("glibunix");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(glibunix);
}
