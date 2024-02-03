const gdesktopenums = @import("gdesktopenums");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gdesktopenums);
}
