const std = @import("std");
const glib = @import("gir-out/glib.zig");
const gobject = @import("gir-out/gobject.zig");
const gtk = @import("gir-out/gtk.zig");

pub fn main() void {
    var app = gtk.Application.new("org.gtk.example", .{});
    defer app.unref();
    _ = app.connectActivate(?*anyopaque, &activate, null);
    const status = app.run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    var window = gtk.ApplicationWindow.new(app);
    window.setTitle("Window");
    window.setDefaultSize(200, 200);

    var box = gtk.Box.new(gtk.Orientation.vertical, 0);
    box.setHalign(gtk.Align.center);
    box.setValign(gtk.Align.center);

    window.setChild(box.asWidget());

    var button = gtk.Button.newWithLabel("Hello World");

    _ = button.connectClicked(?*anyopaque, &printHello, null);
    // TODO: https://github.com/ziglang/zig/issues/14610
    // _ = gobject.signalConnectData(button, "clicked", gobject.callback(&gtk.Window.destroy), window, null, .{ .swapped = true });
    _ = button.connectClicked(*gtk.ApplicationWindow, &closeWindow, window);

    box.append(button.asWidget());

    window.show();
}

fn printHello(_: *gtk.Button, _: ?*anyopaque) callconv(.C) void {
    std.debug.print("Hello World\n", .{});
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.C) void {
    window.destroy();
}
