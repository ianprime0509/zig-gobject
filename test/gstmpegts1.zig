const gstmpegts = @import("gstmpegts");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstmpegts);
}
