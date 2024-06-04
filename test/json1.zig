const json = @import("json");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(json);
}
