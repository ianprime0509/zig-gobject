const std = @import("std");
const glib = @import("gir-out/glib.zig");
const gobject = @import("gir-out/gobject.zig");
const gtk = @import("gir-out/gtk.zig");

pub fn main() void {
    var app = gtk.Application.new("org.gtk.example", .{});
    defer app.unref();
    // TODO: due to https://github.com/ziglang/zig/issues/12325, this doesn't
    // work without manually editing the definition of ClosureNotify
    _ = gobject.signalConnectData(app, "activate", @ptrCast(gobject.Callback, &activate), null, null, .{});
    const status = app.run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}

fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    var window = gtk.ApplicationWindow.new(app);
    window.setTitle("Window");
    window.setDefaultSize(200, 200);

    var box = gtk.Box.new(gtk.Orientation.vertical, 0);
    box.setHalign(gtk.Align.center);
    box.setValign(gtk.Align.center);

    window.setChild(@ptrCast(*gtk.Widget, box));

    var button = gtk.Button.newWithLabel("Hello World");

    _ = gobject.signalConnectData(button, "clicked", @ptrCast(gobject.Callback, &printHello), null, null, .{});
    // TODO: https://github.com/ziglang/zig/issues/14610
    // _ = gobject.signalConnectData(button, "clicked", @ptrCast(gobject.Callback, &gtk.Window.destroy), window, null, .{ .swapped = true });

    box.append(@ptrCast(*gtk.Widget, button));

    window.show();
}

fn printHello(widget: *gtk.Widget, data: ?*anyopaque) callconv(.C) void {
    _ = data;
    _ = widget;
    std.debug.print("Hello World\n", .{});
}
