const notify = @import("notify");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(notify);
}
