const gio = @import("gio");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gio);
}
