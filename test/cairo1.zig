const cairo = @import("cairo");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(cairo);
}
