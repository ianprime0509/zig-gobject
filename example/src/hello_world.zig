// https://docs.gtk.org/gtk4/getting_started.html#hello-world

const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");

pub fn main() void {
    var app = gtk.Application.new("org.gtk.example", .{});
    defer app.unref();
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    var window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "Window");
    gtk.Window.setDefaultSize(window.as(gtk.Window), 200, 200);

    var box = gtk.Box.new(gtk.Orientation.vertical, 0);
    gtk.Widget.setHalign(box.as(gtk.Widget), gtk.Align.center);
    gtk.Widget.setValign(box.as(gtk.Widget), gtk.Align.center);

    gtk.Window.setChild(window.as(gtk.Window), box.as(gtk.Widget));

    var button = gtk.Button.newWithLabel("Hello World");

    _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &printHello, null, .{});
    _ = gtk.Button.signals.clicked.connect(button, *gtk.ApplicationWindow, &closeWindow, window, .{});

    gtk.Box.append(box, button.as(gtk.Widget));

    gtk.Widget.show(window.as(gtk.Widget));
}

fn printHello(_: *gtk.Button, _: ?*anyopaque) callconv(.C) void {
    std.debug.print("Hello World\n", .{});
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.C) void {
    gtk.Window.destroy(window.as(gtk.Window));
}
