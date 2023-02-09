const std = @import("std");
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

fn activate(app: *gtk.Application, user_data: *anyopaque) callconv(.C) void {
    _ = user_data;
    std.log.info("activated", .{});
    var window = gtk.ApplicationWindow.new(app);
    window.setTitle("Window");
    window.setDefaultSize(200, 200);
    window.show();
}
