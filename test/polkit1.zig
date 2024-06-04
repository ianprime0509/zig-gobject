const polkit = @import("polkit");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(polkit);
}
