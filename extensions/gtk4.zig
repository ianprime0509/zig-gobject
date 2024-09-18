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
        ensureWidgetType(@TypeOf(class).Instance, field);
        gtk.Widget.Class.bindTemplateChildFull(
            gobject.ext.as(gtk.Widget.Class, class),
            name,
            @intFromBool(options.internal),
            @offsetOf(@TypeOf(class).Instance, field),
        );
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
