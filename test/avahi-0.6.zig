const avahi = @import("avahi");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(avahi);
}
