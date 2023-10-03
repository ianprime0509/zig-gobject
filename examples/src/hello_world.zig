// https://docs.gtk.org/gtk4/getting_started.html#hello-world

const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

pub fn main() void {
    var app = gtk.Application.new("org.gtk.example", .{});
    defer app.unref();
    _ = app.connectActivate(?*anyopaque, &activate, null, .{});
    const status = app.run(@intCast(std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    var window = gtk.ApplicationWindow.new(app);
    window.setTitle("Window");
    window.setDefaultSize(200, 200);

    var box = gtk.Box.new(gtk.Orientation.vertical, 0);
    box.setHalign(gtk.Align.center);
    box.setValign(gtk.Align.center);

    window.setChild(box.as(gtk.Widget));

    var button = gtk.Button.newWithLabel("Hello World");

    _ = button.connectClicked(?*anyopaque, &printHello, null, .{});
    _ = button.connectClicked(*gtk.ApplicationWindow, &closeWindow, window, .{});

    box.append(button.as(gtk.Widget));

    window.show();
}

fn printHello(_: *gtk.Button, _: ?*anyopaque) callconv(.C) void {
    std.debug.print("Hello World\n", .{});
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.C) void {
    window.destroy();
}
