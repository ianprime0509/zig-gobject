// https://docs.gtk.org/gtk4/getting_started.html#custom-drawing

const std = @import("std");
const gio = @import("gio");
const gtk = @import("gtk");
const gdk = @import("gdk");
const cairo = @import("cairo");
const gobject = @import("gobject");

pub fn main() void {
    const app = gtk.Application.new("org.gtk.example", .{});
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    const window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "Drawing Area");

    _ = gtk.Widget.signals.destroy.connect(window, ?*anyopaque, &closeWindow, null, .{});

    const frame = gtk.Frame.new(null);
    gtk.Window.setChild(window.as(gtk.Window), frame.as(gtk.Widget));

    const drawing_area = gtk.DrawingArea.new();
    gtk.Widget.setSizeRequest(drawing_area.as(gtk.Widget), 100, 100);

    gtk.Frame.setChild(frame, drawing_area.as(gtk.Widget));

    gtk.DrawingArea.setDrawFunc(drawing_area, &drawCb, null, null);

    _ = gtk.DrawingArea.signals.resize.connect(drawing_area, ?*anyopaque, &resizeCb, null, .{ .after = true });

    const drag = gtk.GestureDrag.new();
    gtk.GestureSingle.setButton(drag.as(gtk.GestureSingle), gdk.BUTTON_PRIMARY);
    gtk.Widget.addController(drawing_area.as(gtk.Widget), drag.as(gtk.EventController));
    _ = gtk.GestureDrag.signals.drag_begin.connect(drag, *gtk.DrawingArea, &dragBegin, drawing_area, .{});
    _ = gtk.GestureDrag.signals.drag_update.connect(drag, *gtk.DrawingArea, &dragUpdate, drawing_area, .{});
    _ = gtk.GestureDrag.signals.drag_end.connect(drag, *gtk.DrawingArea, &dragEnd, drawing_area, .{});

    const press = gtk.GestureClick.new();
    gtk.GestureSingle.setButton(press.as(gtk.GestureSingle), gdk.BUTTON_SECONDARY);
    gtk.Widget.addController(drawing_area.as(gtk.Widget), press.as(gtk.EventController));
    _ = gtk.GestureClick.signals.pressed.connect(press, *gtk.DrawingArea, &pressed, drawing_area, .{});

    gtk.Widget.show(window.as(gtk.Widget));
}

var surface: ?*cairo.Surface = null;

fn clearSurface() callconv(.c) void {
    const cr = cairo.Context.create(surface orelse return);
    defer cr.destroy();

    cr.setSourceRgb(1, 1, 1);
    cr.paint();
}

fn resizeCb(widget: *gtk.DrawingArea, _: c_int, _: c_int, _: ?*anyopaque) callconv(.c) void {
    if (surface) |s| {
        s.destroy();
        surface = null;
    }

    const native = gtk.Widget.getNative(widget.as(gtk.Widget)) orelse return;
    const width = gtk.Widget.getWidth(widget.as(gtk.Widget));
    const height = gtk.Widget.getHeight(widget.as(gtk.Widget));
    const native_surface = gtk.Native.getSurface(native) orelse return;
    surface = native_surface.createSimilarSurface(cairo.Content.color, width, height);

    // Initialize the surface to white
    clearSurface();
}

fn drawCb(_: *gtk.DrawingArea, cr: *cairo.Context, _: c_int, _: c_int, _: ?*anyopaque) callconv(.c) void {
    cr.setSourceSurface(surface orelse return, 0, 0);
    cr.paint();
}

fn drawBrush(widget: *gtk.DrawingArea, x: f64, y: f64) callconv(.c) void {
    const cr = cairo.Context.create(surface orelse return);
    defer cr.destroy();

    cr.rectangle(x - 3, y - 3, 6, 6);
    cr.fill();

    gtk.Widget.queueDraw(widget.as(gtk.Widget));
}

var start_x: f64 = 0;
var start_y: f64 = 0;

fn dragBegin(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.c) void {
    start_x = x;
    start_y = y;

    drawBrush(area, x, y);
}

fn dragUpdate(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.c) void {
    drawBrush(area, start_x + x, start_y + y);
}

fn dragEnd(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.c) void {
    drawBrush(area, start_x + x, start_y + y);
}

fn pressed(_: *gtk.GestureClick, _: c_int, _: f64, _: f64, area: *gtk.DrawingArea) callconv(.c) void {
    clearSurface();
    gtk.Widget.queueDraw(area.as(gtk.Widget));
}

fn closeWindow(_: *gtk.ApplicationWindow, _: ?*anyopaque) callconv(.c) void {
    if (surface) |s| {
        s.destroy();
    }
}
