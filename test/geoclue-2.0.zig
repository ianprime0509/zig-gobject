const geoclue = @import("geoclue");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(geoclue);
}
