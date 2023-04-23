const xrandr = @import("xrandr");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(xrandr);
}
