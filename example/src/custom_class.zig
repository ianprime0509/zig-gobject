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

    fn activateImpl(app: *ExampleApplication) callconv(.c) void {
        const win = ExampleApplicationWindow.new(app);
        gtk.Window.present(win.as(gtk.Window));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = ExampleApplication;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
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
        \\            <property name="counter">10</property>
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

    fn init(win: *ExampleApplicationWindow, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(win.as(gtk.Widget));

        _ = ExampleButton.signals.counter_incremented.connect(win.private().button, ?*anyopaque, &handleIncremented, null, .{});
    }

    fn dispose(win: *ExampleApplicationWindow) callconv(.c) void {
        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent, win.as(Parent));
    }

    fn handleIncremented(_: *ExampleButton, new_value: c_uint, _: ?*anyopaque) callconv(.c) void {
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

        fn init(class: *Class) callconv(.c) void {
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

    pub const properties = struct {
        pub const counter = struct {
            pub const name = "counter";
            const impl = gobject.ext.defineProperty(name, ExampleButton, c_uint, .{
                .nick = "Counter",
                .blurb = "The value of the counter.",
                .minimum = 0,
                .maximum = std.math.maxInt(c_uint),
                .default = 0,
                .accessor = gobject.ext.privateFieldAccessor(ExampleButton, Private, &Private.offset, "counter"),
            });
        };
    };

    pub fn as(button: *ExampleButton, comptime T: type) *T {
        return gobject.ext.as(T, button);
    }

    fn init(button: *ExampleButton, _: *Class) callconv(.c) void {
        // TODO: actually, the label should just be implemented using GtkExpression or something
        _ = gobject.Object.signals.notify.connect(button, ?*anyopaque, &handleNotifyCounter, null, .{ .detail = "counter" });
        _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &handleClicked, null, .{});
    }

    fn handleNotifyCounter(button: *ExampleButton, _: *gobject.ParamSpec, _: ?*anyopaque) callconv(.c) void {
        button.updateLabel();
    }

    fn handleClicked(button: *ExampleButton, _: ?*anyopaque) callconv(.c) void {
        var counter = gobject.ext.Value.new(c_uint);
        defer counter.unset();
        gobject.Object.getProperty(button.as(gobject.Object), "counter", &counter);
        gobject.ext.Value.set(&counter, gobject.ext.Value.get(&counter, c_uint) +| 1);
        gobject.Object.setProperty(button.as(gobject.Object), "counter", &counter);
        signals.counter_incremented.impl.emit(button, null, .{gobject.ext.Value.get(&counter, c_uint)}, null);
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

        fn init(class: *Class) callconv(.c) void {
            signals.counter_incremented.impl.register(.{});
            gobject.ext.registerProperties(class, &.{
                properties.counter.impl,
            });
        }
    };
};

pub fn main() void {
    const status = gio.Application.run(ExampleApplication.new().as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}
