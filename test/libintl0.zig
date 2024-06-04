const libintl = @import("libintl");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(libintl);
}
