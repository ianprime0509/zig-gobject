const harfbuzz = @import("harfbuzz");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(harfbuzz);
}
