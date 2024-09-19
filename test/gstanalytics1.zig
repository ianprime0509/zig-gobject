const gstanalytics1 = @import("gstanalytics");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstanalytics1);
}
