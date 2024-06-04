const soup = @import("soup");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(soup);
}
