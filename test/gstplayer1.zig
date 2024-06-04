const gstplayer = @import("gstplayer");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstplayer);
}
