const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;
    const Self = @This();

    pub const getType = gobject.ext.defineType(Self, .{
        .classInit = &Class.init,
    });

    pub fn new() *Self {
        return gobject.ext.newInstance(Self, .{
            .application_id = "org.gtk.exampleapp",
            .flags = gio.ApplicationFlags{ .handles_open = true },
        });
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return gobject.ext.as(T, self);
    }

    fn activateImpl(self: *Self) callconv(.C) void {
        const win = ExampleApplicationWindow.new(self);
        gtk.Window.present(win.as(gtk.Window));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn as(self: *Class, comptime T: type) *T {
            return gobject.ext.as(T, self);
        }

        fn init(self: *Class) callconv(.C) void {
            gio.ApplicationClass.implementActivate(self, &activateImpl);
        }
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

    const Private = struct {
        button: *ExampleButton,

        var offset: c_int = 0;
    };

    pub const getType = gobject.ext.defineType(Self, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(app: *ExampleApplication) *Self {
        return gobject.ext.newInstance(Self, .{
            .application = app,
        });
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return gobject.ext.as(T, self);
    }

    fn init(self: *Self, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));

        _ = ExampleButton.connectCounterIncremented(self.private().button, ?*anyopaque, &handleIncremented, null, .{});
    }

    fn handleIncremented(_: *ExampleButton, new_value: c_uint, _: ?*anyopaque) callconv(.C) void {
        std.debug.print("New button value: {}\n", .{new_value});
    }

    fn private(self: *Self) *Private {
        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn as(self: *Class, comptime T: type) *T {
            return gobject.ext.as(T, self);
        }

        fn init(self: *Class) callconv(.C) void {
            // Ensure the ExampleButton type is registered before handling the
            // template
            _ = ExampleButton.getType();
            gtk.ext.WidgetClass.setTemplateFromSlice(self.as(gtk.WidgetClass), template);
            self.bindTemplateChildPrivate("button", .{});
        }

        fn bindTemplateChildPrivate(self: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(self, name, Private, Private.offset, options);
        }
    };
};

const ExampleButton = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Button;
    const Self = @This();

    const Private = struct {
        counter: c_uint,

        var offset: c_int = 0;
    };

    pub const getType = gobject.ext.defineType(Self, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const counter_incremented = gobject.ext.defineSignal("counter-incremented", Self, &.{c_uint}, void);
    pub const connectCounterIncremented = counter_incremented.connect;

    pub fn as(self: *Self, comptime T: type) *T {
        return gobject.ext.as(T, self);
    }

    fn init(self: *Self, _: *Class) callconv(.C) void {
        _ = gtk.Button.connectClicked(self, ?*anyopaque, &handleClicked, null, .{});

        self.updateLabel();
    }

    fn handleClicked(self: *Self, _: ?*anyopaque) callconv(.C) void {
        self.private().counter +|= 1;
        self.updateLabel();
        counter_incremented.emit(self, null, .{self.private().counter}, null);
    }

    fn updateLabel(self: *Self) void {
        var buf: [64]u8 = undefined;
        gtk.Button.setLabel(self.as(gtk.Button), std.fmt.bufPrintZ(&buf, "Clicked: {}", .{self.private().counter}) catch unreachable);
    }

    fn private(self: *Self) *Private {
        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Self;

        pub fn as(self: *Class, comptime T: type) *T {
            return gobject.ext.as(T, self);
        }

        fn init(_: *Class) callconv(.C) void {
            counter_incremented.register(.{});
        }
    };
};

pub fn main() void {
    const status = gio.Application.run(ExampleApplication.new().as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.os.exit(@intCast(status));
}
