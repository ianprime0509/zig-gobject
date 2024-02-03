const gstbadaudio = @import("gstbadaudio");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstbadaudio);
}
