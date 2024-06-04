const libxml2 = @import("libxml2");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(libxml2);
}
