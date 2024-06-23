const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApplication = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Application;

    pub const getGObjectType = gobject.ext.defineClass(ExampleApplication, .{
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
            gio.Application.virtual_methods.activate.implement(class, &activateImpl);
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

    pub const getGObjectType = gobject.ext.defineClass(ExampleApplicationWindow, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
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

        _ = ExampleButton.signals.counter_incremented.connect(win.private().button, ?*anyopaque, &handleIncremented, null, .{});
    }

    fn dispose(win: *ExampleApplicationWindow) callconv(.C) void {
        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), win.as(gobject.Object));
    }

    fn handleIncremented(_: *ExampleButton, new_value: c_uint, _: ?*anyopaque) callconv(.C) void {
        std.debug.print("New button value: {}\n", .{new_value});
    }

    fn private(win: *ExampleApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = ExampleApplicationWindow;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
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

    pub const getGObjectType = gobject.ext.defineClass(ExampleButton, .{
        .instanceInit = &init,
        .classInit = &Class.init,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub const signals = struct {
        pub const counter_incremented = struct {
            pub const name = "counter-incremented";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(name, ExampleButton, &.{c_uint}, void);
        };
    };

    pub fn as(button: *ExampleButton, comptime T: type) *T {
        return gobject.ext.as(T, button);
    }

    fn init(button: *ExampleButton, _: *Class) callconv(.C) void {
        _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &handleClicked, null, .{});

        button.updateLabel();
    }

    fn handleClicked(button: *ExampleButton, _: ?*anyopaque) callconv(.C) void {
        button.private().counter +|= 1;
        button.updateLabel();
        signals.counter_incremented.impl.emit(button, null, .{button.private().counter}, null);
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
            signals.counter_incremented.impl.register(.{});
        }
    };
};

pub fn main() void {
    const status = gio.Application.run(ExampleApplication.new().as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}
