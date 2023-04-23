const win32 = @import("win32");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(win32);
}
