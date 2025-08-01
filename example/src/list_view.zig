const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");

pub fn main() void {
    const app = gtk.Application.new("org.gtk.example", .{});
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    const window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "Window");
    gtk.Window.setDefaultSize(window.as(gtk.Window), 600, 600);

    const scrolled_window = gtk.ScrolledWindow.new();
    gtk.Window.setChild(window.as(gtk.Window), scrolled_window.as(gtk.Widget));

    const list_model = NumberList.new(1_000_000);
    const selection_model = gtk.SingleSelection.new(list_model.as(gio.ListModel));
    const item_factory = gtk.SignalListItemFactory.new();
    _ = gtk.SignalListItemFactory.signals.setup.connect(item_factory, ?*anyopaque, &setupListItem, null, .{});
    _ = gtk.SignalListItemFactory.signals.bind.connect(item_factory, ?*anyopaque, &bindListItem, null, .{});
    _ = gtk.SignalListItemFactory.signals.unbind.connect(item_factory, ?*anyopaque, &unbindListItem, null, .{});
    const list_view = gtk.ListView.new(selection_model.as(gtk.SelectionModel), item_factory.as(gtk.ListItemFactory));
    gtk.ScrolledWindow.setChild(scrolled_window, list_view.as(gtk.Widget));

    gtk.Widget.show(window.as(gtk.Widget));
}

fn setupListItem(_: *gtk.SignalListItemFactory, list_item_obj: *gobject.Object, _: ?*anyopaque) callconv(.c) void {
    const list_item = gobject.ext.cast(gtk.ListItem, list_item_obj).?;
    const box = gtk.Box.new(.horizontal, 5);
    list_item.setChild(box.as(gtk.Widget));
}

fn bindListItem(_: *gtk.SignalListItemFactory, list_item_obj: *gobject.Object, _: ?*anyopaque) callconv(.c) void {
    const list_item = gobject.ext.cast(gtk.ListItem, list_item_obj).?;
    const number = gobject.ext.cast(Number, list_item.getItem().?).?;
    const box = gobject.ext.cast(gtk.Box, list_item.getChild().?).?;
    var label_value = gobject.ext.Value.new(*gtk.Label);
    defer label_value.unset();
    gobject.Object.getProperty(number.as(gobject.Object), "label", &label_value);
    const label = gobject.ext.Value.get(&label_value, ?*gtk.Widget).?;
    gtk.Widget.setMarginTop(label, 5);
    gtk.Widget.setMarginBottom(label, 5);
    gtk.Widget.setMarginStart(label, 5);
    gtk.Widget.setMarginEnd(label, 5);
    box.append(label);
}

fn unbindListItem(_: *gtk.SignalListItemFactory, list_item_obj: *gobject.Object, _: ?*anyopaque) callconv(.c) void {
    const list_item = gobject.ext.cast(gtk.ListItem, list_item_obj).?;
    const box = list_item.getChild().?;
    while (box.getFirstChild()) |child| child.unparent();
}

const Number = extern struct {
    parent_instance: Parent,
    value: c_uint,

    pub const Parent = gobject.Object;

    pub const getGObjectType = gobject.ext.defineClass(Number, .{
        .classInit = &Class.init,
    });

    pub const properties = struct {
        pub const value = struct {
            pub const name = "value";
            const impl = gobject.ext.defineProperty(name, Number, c_uint, .{
                .nick = "Value",
                .blurb = "The value of the number.",
                .minimum = std.math.minInt(c_uint),
                .maximum = std.math.maxInt(c_uint),
                .default = 0,
                .accessor = gobject.ext.fieldAccessor(Number, "value"),
            });
        };

        pub const label = struct {
            pub const name = "label";
            const impl = gobject.ext.defineProperty(name, Number, ?*gtk.Label, .{
                .nick = "Label",
                .blurb = "A label displaying the number's value",
                .accessor = gobject.ext.typedAccessor(Number, *gtk.Label, .{
                    .getter = &getLabel,
                    // The returned label object is constructed on demand and
                    // will be owned by the caller.
                    .getter_transfer = .full,
                }),
            });
        };
    };

    pub fn new(value: c_uint) *Number {
        return gobject.ext.newInstance(Number, .{ .value = value });
    }

    pub fn as(number: *Number, comptime T: type) *T {
        return gobject.ext.as(T, number);
    }

    fn getLabel(number: *Number) *gtk.Label {
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "Number {}", .{number.value}) catch unreachable;
        const label = gtk.Label.new(text);
        // For the sake of demonstrating the scenario where getter_transfer is
        // set to full, we want label to have a full reference at this point so
        // it can be taken over by the caller. Usually, this would be
        // unnecessary, and we would simply leave getter_transfer as none and do
        // nothing here: since gtk.Label inherits from gobject.InitiallyUnowned,
        // new objects have a "floating" reference, such that the first call to
        // gobject.refSink will actually not increment the reference count, but
        // just convert the floating reference to a full reference.
        _ = gobject.Object.takeRef(label.as(gobject.Object));
        return label;
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Number;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.ext.registerProperties(class, &.{
                properties.value.impl,
                properties.label.impl,
            });
        }
    };
};

const NumberList = extern struct {
    parent_instance: Parent,
    len: c_uint,

    pub const Parent = gobject.Object;
    pub const Implements = [_]type{gio.ListModel};

    pub const getGObjectType = gobject.ext.defineClass(NumberList, .{
        .classInit = &Class.init,
        .implements = &.{
            gobject.ext.implement(gio.ListModel, .{ .init = Class.initListModel }),
        },
    });

    pub const properties = struct {
        pub const len = struct {
            pub const name = "len";
            const impl = gobject.ext.defineProperty(name, NumberList, c_uint, .{
                .nick = "Length",
                .blurb = "The length of the list.",
                .minimum = 0,
                .maximum = std.math.maxInt(c_uint),
                .default = 0,
                .accessor = gobject.ext.typedAccessor(NumberList, c_uint, .{
                    .getter = &getLenInternal,
                    .setter = &setLenInternal,
                }),
            });
        };
    };

    pub fn new(len: c_uint) *NumberList {
        return gobject.ext.newInstance(NumberList, .{ .len = len });
    }

    pub fn as(list: *NumberList, comptime T: type) *T {
        return gobject.ext.as(T, list);
    }

    pub fn getItem(list_model: *gio.ListModel, position: c_uint) callconv(.c) ?*gobject.Object {
        const list = gobject.ext.cast(NumberList, list_model).?;
        return if (position < list.len) Number.new(position).as(gobject.Object) else null;
    }

    pub fn getItemType(_: *gio.ListModel) callconv(.c) gobject.Type {
        return Number.getGObjectType();
    }

    pub fn getNItems(list_model: *gio.ListModel) callconv(.c) c_uint {
        const list = gobject.ext.cast(NumberList, list_model).?;
        return list.len;
    }

    fn getLenInternal(list: *NumberList) c_uint {
        return list.len;
    }

    fn setLenInternal(list: *NumberList, len: c_uint) void {
        const old_len = list.len;
        list.len = len;
        if (len > old_len) {
            gio.ListModel.itemsChanged(list.as(gio.ListModel), old_len, 0, len - old_len);
        } else if (len < old_len) {
            gio.ListModel.itemsChanged(list.as(gio.ListModel), len, old_len - len, 0);
        }
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = NumberList;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.ext.registerProperties(class, &.{
                properties.len.impl,
            });
        }

        fn initListModel(iface: *gio.ListModel.Iface) callconv(.c) void {
            gio.ListModel.virtual_methods.get_item.implement(iface, getItem);
            gio.ListModel.virtual_methods.get_item_type.implement(iface, getItemType);
            gio.ListModel.virtual_methods.get_n_items.implement(iface, getNItems);
        }
    };
};
