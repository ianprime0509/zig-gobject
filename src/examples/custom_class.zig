const std = @import("std");
const gtk = @import("../gir-out/gtk-4.0.zig");
const gio = @import("../gir-out/gio-2.0.zig");
const gobject = @import("../gir-out/gobject-2.0.zig");
const glib = @import("../gir-out/glib-2.0.zig");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;
    const Self = @This();

    pub const getType = gobject.registerType(Self, .{});

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

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub fn init(self: *Class) callconv(.C) void {
            self.implementActivate(&ExampleApplication.activateImpl);
        }

        pub usingnamespace Parent.Class.Methods(Class);
        pub usingnamespace Parent.Class.VirtualMethods(Class, Self);
    };
};

const ExampleApplicationWindow = extern struct {
    parent_instance: Parent,

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

    pub const Parent = gtk.ApplicationWindow;
    const Self = @This();

    pub const getType = gobject.registerType(Self, .{});

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

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub fn init(self: *Class) callconv(.C) void {
            self.setTemplate(glib.Bytes.newFromSlice(template));
        }

        pub usingnamespace Parent.Class.Methods(Class);
        pub usingnamespace Parent.Class.VirtualMethods(Class, Self);
    };
};

pub fn main() void {
    const status = ExampleApplication.new().run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}
