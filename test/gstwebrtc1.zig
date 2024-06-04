const gstwebrtc = @import("gstwebrtc");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstwebrtc);
}
