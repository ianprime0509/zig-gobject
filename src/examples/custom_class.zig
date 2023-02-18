const std = @import("std");
const gtk = @import("../gir-out/gtk.zig");
const gio = @import("../gir-out/gio.zig");
const gobject = @import("../gir-out/gobject.zig");
const glib = @import("../gir-out/glib.zig");

const ExampleApplication = extern struct {
    parent_instance: gtk.Application,

    const Self = @This();

    pub const getType = gobject.registerType(Self, .{ .Parent = gtk.Application });

    pub fn new() *Self {
        return @ptrCast(*Self, gobject.Object.new(
            getType(),
            "application-id",
            "org.gtk.exampleapp",
            "flags",
            gio.ApplicationFlags{ .handles_open = true },
            @as(?*anyopaque, null),
        ));
    }

    // TODO: is there some nice way to make this not public? (etc. for other lifecycle methods)
    pub fn init(_: *Self) callconv(.C) void {}

    fn activateImpl(self: *Self) callconv(.C) void {
        const win = ExampleApplicationWindow.new(self);
        win.present();
    }

    pub usingnamespace gtk.ApplicationMethods(Self);

    pub const Class = extern struct {
        parent_class: gtk.ApplicationClass,

        pub fn init(self: *Class) callconv(.C) void {
            self.implementActivate(&ExampleApplication.activateImpl);
        }

        pub usingnamespace gtk.ApplicationVirtualMethods(Class, Self);
    };
};

const ExampleApplicationWindow = extern struct {
    parent_instance: gtk.ApplicationWindow,

    const template =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<interface>
        \\  <template class="ExampleApplicationWindow" parent="GtkApplicationWindow">
        \\    <property name="title" translatable="yes">Example Application</property>
        \\    <property name="default-width">600</property>
        \\    <property name="default-height">400</property>
        \\    <child>
        \\      <object class="GtkLabel" id="hello_label">
        \\        <property name="halign">center</property>
        \\        <property name="valign">center</property>
        \\        <property name="label">Hello, world!</property>
        \\      </object>
        \\    </child>
        \\  </template>
        \\</interface>
    ;

    const Self = @This();

    pub const getType = gobject.registerType(Self, .{ .Parent = gtk.ApplicationWindow });

    pub fn new(app: *ExampleApplication) *Self {
        return @ptrCast(*Self, gobject.Object.new(
            getType(),
            "application",
            app,
            @as(?*anyopaque, null),
        ));
    }

    pub fn init(self: *Self) callconv(.C) void {
        self.initTemplate();
    }

    pub usingnamespace gtk.ApplicationWindowMethods(Self);

    pub const Class = extern struct {
        parent_class: gtk.ApplicationWindowClass,

        pub fn init(self: *Class) callconv(.C) void {
            // TODO: "inheritance" of class methods
            @ptrCast(*gtk.WidgetClass, self).setTemplate(glib.Bytes.newStatic(@constCast(template), template.len));
        }

        pub usingnamespace gtk.ApplicationWindowVirtualMethods(Class, Self);
    };
};

pub fn main() void {
    const status = ExampleApplication.new().run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}
