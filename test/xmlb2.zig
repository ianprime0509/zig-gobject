const xmlb = @import("xmlb");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(xmlb);
}
