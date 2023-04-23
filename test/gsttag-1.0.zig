const gsttag = @import("gsttag");
const bindings = @import("bindings.zig");

test "bindings" {
	bindings.refAllBindings(gsttag);
}
