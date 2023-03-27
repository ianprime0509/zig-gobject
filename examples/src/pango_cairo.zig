// Adapted from https://docs.gtk.org/PangoCairo/pango_cairo.html#using-pango-with-cairo

const std = @import("std");
const math = std.math;
const gtk = @import("gtk");
const cairo = @import("cairo");
const pango = @import("pango");
const pangocairo = @import("pangocairo");

const n_words = 10;
const font = "Sans Bold 27";

fn draw(_: *gtk.DrawingArea, cr: *cairo.Context, draw_width: c_int, draw_height: c_int, _: ?*anyopaque) callconv(.C) void {
    cr.translate(@intToFloat(f64, draw_width) / 2, @intToFloat(f64, draw_height) / 2);
    const radius = @intToFloat(f64, @min(draw_width, draw_height)) / 2;

    const layout = pangocairo.createLayout(cr);
    defer layout.unref();
    layout.setText("Text", -1);
    const desc = pango.FontDescription.fromString(font);
    defer desc.free();
    layout.setFontDescription(desc);

    for (0..n_words) |i| {
        cr.save();
        defer cr.restore();

        const angle = 360 * @intToFloat(f64, i) / n_words;
        const red = (1 + math.cos((angle - 60) * math.pi / 180)) / 2;
        cr.setSourceRgb(red, 0, 1 - red);
        cr.rotate(angle * math.pi / 180);
        pangocairo.updateLayout(cr, layout);

        var width: c_int = undefined;
        layout.getSize(&width, null);
        cr.moveTo(-@intToFloat(f64, width) / @intToFloat(f64, pango.SCALE) / 2, -radius);
        pangocairo.showLayout(cr, layout);
    }
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = gtk.ApplicationWindow.new(app);
    window.setTitle("PangoCairo text example");
    window.setDefaultSize(300, 300);

    const drawing_area = gtk.DrawingArea.new();
    drawing_area.setHexpand(true);
    drawing_area.setVexpand(true);
    _ = drawing_area.setDrawFunc(&draw, null, null);
    window.setChild(drawing_area.as(gtk.Widget));

    window.show();
}

pub fn main() void {
    const app = gtk.Application.new("org.gtk.example", .{});
    _ = app.connectActivate(?*anyopaque, &activate, null, .{});
    const status = app.run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}
