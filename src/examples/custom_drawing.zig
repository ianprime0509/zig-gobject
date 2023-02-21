// https://docs.gtk.org/gtk4/getting_started.html#custom-drawing

// TODO: this example doesn't work yet because Cairo doesn't actually have
// proper gobject-introspection metadata

const std = @import("std");
const gtk = @import("../gir-out/gtk-4.0.zig");
const gdk = @import("../gir-out/gdk-4.0.zig");
const cairo = @import("../gir-out/cairo-1.0.zig");
const gobject = @import("../gir-out/gobject-2.0.zig");

pub fn main() void {
    const app = gtk.Application.new("org.gtk.example", .{});
    _ = app.connectActivate(?*anyopaque, &activate, null);
    const status = app.run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = gtk.ApplicationWindow.new(app);
    window.setTitle("Drawing Area");

    _ = window.connectDestroy(?*anyopaque, &closeWindow, null);

    const frame = gtk.Frame.new(null);
    window.setChild(frame.as(gtk.Widget));

    const drawing_area = gtk.DrawingArea.new();
    drawing_area.setSizeRequest(100, 100);

    frame.setChild(drawing_area.as(gtk.Widget));

    drawing_area.setDrawFunc(&drawCb, null, null);

    _ = gobject.signalConnectData(drawing_area, "resize", @ptrCast(*gobject.Callback, &resizeCb), null, null, .{ .after = true });

    const drag = gtk.GestureDrag.new();
    drag.setButton(gdk.BUTTON_PRIMARY);
    drawing_area.addController(drag.as(gtk.EventController));
    _ = drag.connectDragBegin(*gtk.DrawingArea, &dragBegin, drawing_area);
    _ = drag.connectDragUpdate(*gtk.DrawingArea, &dragUpdate, drawing_area);
    _ = drag.connectDragEnd(*gtk.DrawingArea, &dragEnd, drawing_area);

    const press = gtk.GestureClick.new();
    press.setButton(gdk.BUTTON_SECONDARY);
    drawing_area.addController(press.as(gtk.EventController));
    _ = press.connectPressed(*gtk.DrawingArea, &pressed, drawing_area);

    window.show();
}

var surface: ?*cairo.Surface = null;

fn clearSurface() callconv(.C) void {
    const cr = cairo.Context.create(surface.?);
    defer cr.destroy();

    cr.setSourceRgb(1, 1, 1);
    cr.paint();
}

fn resizeCb(widget: *gtk.DrawingArea, _: c_int, _: c_int, _: ?*anyopaque) callconv(.C) void {
    if (surface) |s| {
        s.destroy();
        surface = null;
    }

    if (widget.getNative().getSurface()) |widget_surface| {
        surface = widget_surface.createSimilarSurface(cairo.CONTENT_COLOR, widget.getWidth(), widget.getHeight());

        // Initialize the surface to white
        clearSurface();
    }
}

fn drawCb(_: *gtk.DrawingArea, cr: *cairo.Context, _: c_int, _: c_int, _: ?*anyopaque) callconv(.C) void {
    cr.setSourceSurface(surface.?, 0, 0);
    cr.paint();
}

fn drawBrush(widget: *gtk.DrawingArea, x: f64, y: f64) callconv(.C) void {
    const cr = cairo.Context.create(surface.?);
    defer cr.destroy();

    cr.rectangle(x - 3, y - 3, 6, 6);
    cr.fill();

    widget.queueDraw();
}

var start_x: f64 = 0;
var start_y: f64 = 0;

fn dragBegin(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.C) void {
    start_x = x;
    start_y = y;

    drawBrush(area, x, y);
}

fn dragUpdate(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.C) void {
    drawBrush(area, start_x + x, start_y + y);
}

fn dragEnd(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.DrawingArea) callconv(.C) void {
    drawBrush(area, start_x + x, start_y + y);
}

fn pressed(_: *gtk.GestureClick, _: c_int, _: f64, _: f64, area: *gtk.DrawingArea) callconv(.C) void {
    clearSurface();
    area.queueDraw();
}

fn closeWindow(_: *gtk.ApplicationWindow, _: ?*anyopaque) callconv(.C) void {
    if (surface) |s| {
        s.destroy();
    }
}
