const tsparql3 = @import("tsparql");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(tsparql3);
}
