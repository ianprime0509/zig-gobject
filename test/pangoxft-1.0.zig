const pangoxft = @import("pangoxft");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(pangoxft);
}
