const appstreamglib = @import("appstreamglib");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(appstreamglib);
}
