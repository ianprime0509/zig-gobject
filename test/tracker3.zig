const tracker = @import("tracker");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(tracker);
}
