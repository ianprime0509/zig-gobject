const javascriptcore = @import("javascriptcore");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(javascriptcore);
}
