const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;

    pub const getType = gobject.ext.defineType(ExampleApplication, .{
        .classInit = &Class.init,
    });

    pub fn new() *ExampleApplication {
        return gobject.ext.newInstance(ExampleApplication, .{
            .application_id = "org.gtk.exampleapp",
            .flags = gio.ApplicationFlags{ .handles_open = true },
        });
    }

    pub fn as(app: *ExampleApplication, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    fn activateImpl(app: *ExampleApplication) callconv(.C) void {
        const win = ExampleApplicationWindow.new(app);
        gtk.Window.present(win.as(gtk.Window));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = ExampleApplication;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gio.ApplicationClass.implementActivate(class, &activateImpl);
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

    const Private = struct {
        button: *ExampleButton,

        var offset: c_int = 0;
    };

    pub const getType = gobject.ext.defineType(ExampleApplicationWindow, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(app: *ExampleApplication) *ExampleApplicationWindow {
        return gobject.ext.newInstance(ExampleApplicationWindow, .{
            .application = app,
        });
    }

    pub fn as(win: *ExampleApplicationWindow, comptime T: type) *T {
        return gobject.ext.as(T, win);
    }

    fn init(win: *ExampleApplicationWindow, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(win.as(gtk.Widget));

        _ = ExampleButton.connectCounterIncremented(win.private().button, ?*anyopaque, &handleIncremented, null, .{});
    }

    fn handleIncremented(_: *ExampleButton, new_value: c_uint, _: ?*anyopaque) callconv(.C) void {
        std.debug.print("New button value: {}\n", .{new_value});
    }

    fn private(win: *ExampleApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = ExampleApplicationWindow;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            // Ensure the ExampleButton type is registered before handling the
            // template
            _ = ExampleButton.getType();
            gtk.ext.WidgetClass.setTemplateFromSlice(class.as(gtk.WidgetClass), template);
            class.bindTemplateChildPrivate("button", .{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};

const ExampleButton = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Button;

    const Private = struct {
        counter: c_uint,

        var offset: c_int = 0;
    };

    pub const getType = gobject.ext.defineType(ExampleButton, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const counter_incremented = gobject.ext.defineSignal("counter-incremented", ExampleButton, &.{c_uint}, void);
    pub const connectCounterIncremented = counter_incremented.connect;

    pub fn as(button: *ExampleButton, comptime T: type) *T {
        return gobject.ext.as(T, button);
    }

    fn init(button: *ExampleButton, _: *Class) callconv(.C) void {
        _ = gtk.Button.connectClicked(button, ?*anyopaque, &handleClicked, null, .{});

        button.updateLabel();
    }

    fn handleClicked(button: *ExampleButton, _: ?*anyopaque) callconv(.C) void {
        button.private().counter +|= 1;
        button.updateLabel();
        counter_incremented.emit(button, null, .{button.private().counter}, null);
    }

    fn updateLabel(button: *ExampleButton) void {
        var buf: [64]u8 = undefined;
        gtk.Button.setLabel(button.as(gtk.Button), std.fmt.bufPrintZ(&buf, "Clicked: {}", .{button.private().counter}) catch unreachable);
    }

    fn private(button: *ExampleButton) *Private {
        return gobject.ext.impl_helpers.getPrivate(button, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = ExampleButton;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
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
