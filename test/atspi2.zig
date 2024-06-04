const atspi = @import("atspi");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(atspi);
}
