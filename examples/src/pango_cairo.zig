// Adapted from https://docs.gtk.org/PangoCairo/pango_cairo.html#using-pango-with-cairo

const std = @import("std");
const math = std.math;
const gio = @import("gio");
const gtk = @import("gtk");
const cairo = @import("cairo");
const pango = @import("pango");
const pangocairo = @import("pangocairo");

const n_words = 10;
const font = "Sans Bold 27";

fn draw(_: *gtk.DrawingArea, cr: *cairo.Context, draw_width: c_int, draw_height: c_int, _: ?*anyopaque) callconv(.C) void {
    cr.translate(@as(f64, @floatFromInt(draw_width)) / 2, @as(f64, @floatFromInt(draw_height)) / 2);
    const radius = @as(f64, @floatFromInt(@min(draw_width, draw_height))) / 2;

    const layout = pangocairo.createLayout(cr);
    defer layout.unref();
    layout.setText("Text", -1);
    const desc = pango.FontDescription.fromString(font);
    defer desc.free();
    layout.setFontDescription(desc);

    for (0..n_words) |i| {
        cr.save();
        defer cr.restore();

        const angle = 360 * @as(f64, @floatFromInt(i)) / n_words;
        const red = (1 + math.cos((angle - 60) * math.pi / 180)) / 2;
        cr.setSourceRgb(red, 0, 1 - red);
        cr.rotate(angle * math.pi / 180);
        pangocairo.updateLayout(cr, layout);

        var width: c_int = undefined;
        layout.getSize(&width, null);
        cr.moveTo(-@as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(pango.SCALE)) / 2, -radius);
        pangocairo.showLayout(cr, layout);
    }
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "PangoCairo text example");
    gtk.Window.setDefaultSize(window.as(gtk.Window), 300, 300);

    const drawing_area = gtk.DrawingArea.new();
    gtk.Widget.setHexpand(drawing_area.as(gtk.Widget), 1);
    gtk.Widget.setVexpand(drawing_area.as(gtk.Widget), 1);
    _ = gtk.DrawingArea.setDrawFunc(drawing_area, &draw, null, null);
    gtk.Window.setChild(window.as(gtk.Window), drawing_area.as(gtk.Widget));

    gtk.Widget.show(window.as(gtk.Widget));
}

pub fn main() void {
    const app = gtk.Application.new("org.gtk.example", .{});
    _ = gio.Application.connectActivate(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(status));
}
