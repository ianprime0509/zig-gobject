const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;
    const Self = @This();

    pub const getType = gobject.defineType(Self, .{});

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
        pub usingnamespace Parent.VirtualMethods(Class, Self);
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
        \\      <object class="GtkBox">
        \\        <property name="orientation">vertical</property>
        \\        <property name="spacing">10</property>
        \\        <property name="margin-top">10</property>
        \\        <property name="margin-bottom">10</property>
        \\        <property name="margin-start">10</property>
        \\        <property name="margin-end">10</property>
        \\        <child>
        \\          <object class="GtkLabel">
        \\            <property name="label">Click the button!</property>
        \\            <property name="halign">0.5</property>
        \\          </object>
        \\        </child>
        \\        <child>
        \\          <object class="ExampleButton" id="button">
        \\            <property name="halign">0.5</property>
        \\            <property name="hexpand">0</property>
        \\          </object>
        \\        </child>
        \\      </object>
        \\    </child>
        \\  </template>
        \\</interface>
    ;

    pub const Parent = gtk.ApplicationWindow;
    const Self = @This();

    pub const Private = struct {
        button: *ExampleButton,

        pub var offset: c_int = 0;
    };

    pub const getType = gobject.defineType(Self, .{});

    pub fn new(app: *ExampleApplication) *Self {
        return Self.newWith(.{ .application = app });
    }

    pub fn init(self: *Self, _: *Class) callconv(.C) void {
        self.initTemplate();

        _ = self.private().button.connectCounterIncremented(?*anyopaque, &handleIncremented, null, .{});
    }

    fn handleIncremented(_: *ExampleButton, new_value: c_uint, _: ?*anyopaque) callconv(.C) void {
        std.debug.print("New button value: {}\n", .{new_value});
    }

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn init(self: *Class) callconv(.C) void {
            // Ensure the ExampleButton type is registered before handling the
            // template
            _ = ExampleButton.getType();
            self.setTemplateFromSlice(template);
            self.bindTemplateChild("button", .{ .private = true });
        }

        pub usingnamespace Parent.Class.Methods(Class);
        pub usingnamespace Parent.VirtualMethods(Class, Self);
    };
};

const ExampleButton = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Button;
    const Self = @This();

    pub const Private = struct {
        counter: c_uint,

        pub var offset: c_int = 0;
    };

    pub const getType = gobject.defineType(Self, .{});

    const counter_incremented = gobject.defineSignal("counter-incremented", *Self, &.{c_uint}, void);
    pub const connectCounterIncremented = counter_incremented.connect;

    pub fn init(self: *Self, _: *Class) callconv(.C) void {
        _ = self.connectClicked(?*anyopaque, &handleClicked, null, .{});

        self.updateLabel();
    }

    fn handleClicked(self: *Self, _: ?*anyopaque) callconv(.C) void {
        self.private().counter +|= 1;
        self.updateLabel();
        counter_incremented.emit(self, null, .{self.private().counter}, null);
    }

    fn updateLabel(self: *Self) void {
        var buf: [64]u8 = undefined;
        self.setLabel(std.fmt.bufPrintZ(&buf, "Clicked: {}", .{self.private().counter}) catch unreachable);
    }

    pub usingnamespace Parent.Methods(Self);

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn init(_: *Class) callconv(.C) void {
            counter_incremented.register(.{});
        }

        pub usingnamespace Parent.Class.Methods(Class);
        pub usingnamespace Parent.VirtualMethods(Class, Self);
    };
};

pub fn main() void {
    const status = ExampleApplication.new().run(@intCast(c_int, std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(u8, status));
}
