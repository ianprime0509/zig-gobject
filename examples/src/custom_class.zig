const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;
    const Self = @This();

    pub const getType = gobject.registerType(Self, .{});

    pub fn new() *Self {
        return Self.newWith(.{
            .application_id = "org.gtk.exampleapp",
            .flags = gio.ApplicationFlags{ .handles_open = true },
        });
    }

    fn activateImpl(self: *Self) callconv(.C) void {
        const win = ExampleApplicationWindow.new(self);
        win.present();
    }

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

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

    pub const Private = struct {
        hello_label: *gtk.Label,

        pub var offset: c_int = 0;
    };

    pub const getType = gobject.registerType(Self, .{});

    pub fn new(app: *ExampleApplication) *Self {
        return Self.newWith(.{ .application = app });
    }

    pub fn init(self: *Self, _: *Class) callconv(.C) void {
        self.initTemplate();
        std.debug.print("label text = '{s}'\n", .{self.private().hello_label.getText()});
    }

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn init(self: *Class) callconv(.C) void {
            self.setTemplateFromSlice(template);
            self.bindTemplateChild("hello_label", .{ .private = true });
        }

        pub usingnamespace Parent.Class.Methods(Class);
        pub usingnamespace Parent.Class.VirtualMethods(Class, Self);
    };
};

pub fn main() void {
    const status = ExampleApplication.new().run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}
