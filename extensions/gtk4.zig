const glib = @import("glib2");
const gobject = @import("gobject2");
const gtk = @import("gtk4");
const std = @import("std");
const compat = @import("compat");

pub const BindTemplateChildOptions = struct {
    field: ?[]const u8 = null,
    internal: bool = false,
};

/// Implementation helpers not meant to be used outside implementations of
/// new classes.
pub const impl_helpers = struct {
    /// Binds a field of the instance struct to an object declared in the
    /// class template.
    ///
    /// The name of the field in the instance struct defaults to the name of
    /// the template object, but can be set explicitly via the `field` option
    /// if it differs.
    pub fn bindTemplateChild(
        class: anytype,
        comptime name: [:0]const u8,
        comptime options: gtk.ext.BindTemplateChildOptions,
    ) void {
        const field = options.field orelse name;
        const Instance = compat.typeInfo(@TypeOf(class)).pointer.child.Instance;
        ensureWidgetType(Instance, field);
        gtk.Widget.Class.bindTemplateChildFull(
            gobject.ext.as(gtk.Widget.Class, class),
            name,
            @intFromBool(options.internal),
            @offsetOf(Instance, field),
        );
    }

    test bindTemplateChild {
        const MyWidget = extern struct {
            parent_instance: Parent,
            label: *gtk.Label,

            const template =
                \\<?xml version="1.0" encoding="UTF-8"?>
                \\<interface>
                \\  <template class="BindTemplateChildTest_MyWidget" parent="GtkWidget">
                \\    <child>
                \\      <object class="GtkLabel" id="label">
                \\        <property name="label">Hello, world!</property>
                \\      </object>
                \\    </child>
                \\  </template>
                \\</interface>
                \\
            ;

            pub const Parent = gtk.Widget;
            const Self = @This();

            pub const getGObjectType = gobject.ext.defineClass(Self, .{
                .name = "BindTemplateChildTest_MyWidget",
                .instanceInit = &init,
                .classInit = &Class.init,
                .parent_class = &Class.parent,
            });

            pub fn as(widget: *Self, comptime T: type) *T {
                return gobject.ext.as(T, widget);
            }

            pub fn new() *Self {
                return gobject.ext.newInstance(Self, .{});
            }

            pub fn unref(widget: *Self) void {
                gobject.Object.unref(widget.as(gobject.Object));
            }

            fn init(widget: *Self, _: *Class) callconv(.C) void {
                gtk.Widget.initTemplate(widget.as(gtk.Widget));
                gtk.Widget.setLayoutManager(widget.as(gtk.Widget), gtk.BinLayout.new().as(gtk.LayoutManager));
            }

            fn dispose(widget: *Self) callconv(.C) void {
                gtk.Widget.disposeTemplate(widget.as(gtk.Widget), getGObjectType());
                gobject.Object.virtual_methods.dispose.call(Class.parent, widget.as(Parent));
            }

            pub const Class = extern struct {
                parent_class: Parent.Class,

                var parent: *Parent.Class = undefined;

                pub const Instance = Self;

                pub fn as(class: *Class, comptime T: type) *T {
                    return gobject.ext.as(T, class);
                }

                fn init(class: *Class) callconv(.C) void {
                    gobject.Object.virtual_methods.dispose.implement(class, &dispose);
                    gtk.ext.WidgetClass.setTemplateFromSlice(class.as(gtk.Widget.Class), template);
                    class.bindTemplateChild("label", .{});
                }

                fn bindTemplateChild(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
                    gtk.ext.impl_helpers.bindTemplateChild(class, name, options);
                }
            };
        };

        gtk.init();
        const widget = MyWidget.new();
        _ = gobject.Object.refSink(widget.as(gobject.Object));
        defer widget.unref();
        try std.testing.expectEqualStrings("Hello, world!", std.mem.span(widget.label.getLabel()));
    }

    /// Binds a template child to a private field.
    ///
    /// ```zig
    /// fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.BindTemplateChildOptions) void {
    ///     gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
    /// }
    /// ```
    pub fn bindTemplateChildPrivate(
        class: anytype,
        comptime name: [:0]const u8,
        comptime Private: type,
        private_offset: c_int,
        comptime options: gtk.ext.BindTemplateChildOptions,
    ) void {
        const field = options.field orelse name;
        ensureWidgetType(Private, field);
        gtk.Widget.Class.bindTemplateChildFull(
            gobject.ext.as(gtk.Widget.Class, class),
            name,
            @intFromBool(options.internal),
            private_offset + @offsetOf(Private, field),
        );
    }

    test bindTemplateChildPrivate {
        const MyWidget = extern struct {
            parent_instance: Parent,

            const template =
                \\<?xml version="1.0" encoding="UTF-8"?>
                \\<interface>
                \\  <template class="BindTemplateChildPrivateTest_MyWidget" parent="GtkWidget">
                \\    <child>
                \\      <object class="GtkLabel" id="label">
                \\        <property name="label">Hello, world!</property>
                \\      </object>
                \\    </child>
                \\  </template>
                \\</interface>
                \\
            ;

            pub const Parent = gtk.Widget;
            const Self = @This();

            const Private = struct {
                label: *gtk.Label,

                var offset: c_int = 0;
            };

            pub const getGObjectType = gobject.ext.defineClass(Self, .{
                .name = "BindTemplateChildPrivateTest_MyWidget",
                .instanceInit = &init,
                .classInit = &Class.init,
                .parent_class = &Class.parent,
                .private = .{ .Type = Private, .offset = &Private.offset },
            });

            pub fn as(widget: *Self, comptime T: type) *T {
                return gobject.ext.as(T, widget);
            }

            pub fn new() *Self {
                return gobject.ext.newInstance(Self, .{});
            }

            pub fn unref(widget: *Self) void {
                gobject.Object.unref(widget.as(gobject.Object));
            }

            pub fn getLabel(widget: *Self) [:0]const u8 {
                return std.mem.span(widget.private().label.getLabel());
            }

            fn init(widget: *Self, _: *Class) callconv(.C) void {
                gtk.Widget.initTemplate(widget.as(gtk.Widget));
                gtk.Widget.setLayoutManager(widget.as(gtk.Widget), gtk.BinLayout.new().as(gtk.LayoutManager));
            }

            fn dispose(widget: *Self) callconv(.C) void {
                gtk.Widget.disposeTemplate(widget.as(gtk.Widget), getGObjectType());
                gobject.Object.virtual_methods.dispose.call(Class.parent, widget.as(Parent));
            }

            fn private(widget: *Self) *Private {
                return gobject.ext.impl_helpers.getPrivate(widget, Private, Private.offset);
            }

            pub const Class = extern struct {
                parent_class: Parent.Class,

                var parent: *Parent.Class = undefined;

                pub const Instance = Self;

                pub fn as(class: *Class, comptime T: type) *T {
                    return gobject.ext.as(T, class);
                }

                fn init(class: *Class) callconv(.C) void {
                    gobject.Object.virtual_methods.dispose.implement(class, &dispose);
                    gtk.ext.WidgetClass.setTemplateFromSlice(class.as(gtk.Widget.Class), template);
                    class.bindTemplateChildPrivate("label", .{});
                }

                fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
                    gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
                }
            };
        };

        gtk.init();
        const widget = MyWidget.new();
        _ = gobject.Object.refSink(widget.as(gobject.Object));
        defer widget.unref();
        try std.testing.expectEqualStrings("Hello, world!", widget.getLabel());
    }

    fn ensureWidgetType(comptime Container: type, comptime field_name: []const u8) void {
        inline for (compat.typeInfo(Container).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, field_name)) {
                const WidgetType = switch (compat.typeInfo(field.type)) {
                    .pointer => |pointer| widget_type: {
                        if (pointer.size != .One) {
                            @compileError("bound child type must be a single pointer");
                        }
                        break :widget_type pointer.child;
                    },
                    .optional => |optional| switch (compat.typeInfo(optional.child)) {
                        .pointer => |pointer| widget_type: {
                            if (pointer.size != .One) {
                                @compileError("bound child type must be a single pointer");
                            }
                            break :widget_type pointer.child;
                        },
                        else => @compileError("unrecognized bound child type"),
                    },
                    else => @compileError("unrecognized bound child type"),
                };
                if (!gobject.ext.isAssignableFrom(gtk.Widget, WidgetType)) {
                    @compileError("bound child must be a widget");
                }
                // Ensuring the type is registered avoids the user needing to
                // explicitly call ensureType on the widget type as long as it's
                // bound as a child in some custom widget class.
                gobject.ext.ensureType(WidgetType);
                break;
            }
        }
    }
};

pub const WidgetClass = struct {
    /// Sets the template for a widget from a byte slice.
    pub fn setTemplateFromSlice(class: *gtk.WidgetClass, template: [:0]const u8) void {
        var bytes = glib.ext.Bytes.newFromSlice(template);
        defer bytes.unref();
        class.setTemplate(bytes);
    }
};
