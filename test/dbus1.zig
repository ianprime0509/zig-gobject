const dbus = @import("dbus");
const bindings = @import("bindings.zig");

test "bindings" {
    bindings.refAllBindings(dbus);
}
