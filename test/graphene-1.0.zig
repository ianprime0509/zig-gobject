const graphene = @import("graphene");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(graphene);
}
