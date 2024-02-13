const glib = @import("glib");

const std = @import("std");
const bindings = @import("bindings.zig");
const testing = std.testing;
const expectEqualStrings = testing.expectEqualStrings;

test "bindings" {
    bindings.refAllBindings(glib);
}

test "Bytes.getDataSlice" {
    const null_ptr = glib.Bytes.new(null, 0);
    defer null_ptr.unref();
    try expectEqualStrings("", glib.ext.Bytes.getDataSlice(null_ptr));

    const empty = glib.ext.Bytes.newFromSlice("");
    defer empty.unref();
    try expectEqualStrings("", glib.ext.Bytes.getDataSlice(empty));

    const non_empty = glib.ext.Bytes.newFromSlice("Hello");
    defer non_empty.unref();
    try expectEqualStrings("Hello", glib.ext.Bytes.getDataSlice(non_empty));
}
