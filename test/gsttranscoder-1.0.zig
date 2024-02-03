const gsttranscoder = @import("gsttranscoder");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(gsttranscoder);
}
