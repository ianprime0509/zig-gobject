const appstreamcompose = @import("appstreamcompose");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(appstreamcompose);
}
