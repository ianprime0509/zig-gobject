const pangoot = @import("pangoot");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pangoot);
}
