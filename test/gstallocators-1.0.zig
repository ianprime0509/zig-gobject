const gstallocators = @import("gstallocators");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gstallocators);
}
