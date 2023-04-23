const adw = @import("adw");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(adw);
}
