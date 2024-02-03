const avahicore = @import("avahicore");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(avahicore);
}
