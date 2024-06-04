const appstream = @import("appstream");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(appstream);
}
