const glib = @import("glib2");
const gtk = @import("gtk4");

pub const BindTemplateChildOptions = struct {
    field: ?[]const u8 = null,
    internal: bool = false,
};

/// Implementation helpers not meant to be used outside implementations of
/// new classes.
pub const impl_helpers = struct {
    /// Binds a template child to a private field.
    ///
    /// ```zig
    /// fn bindTemplateChildPrivate(self: *Class, comptime name: [:0]const u8, comptime options: gtk.BindTemplateChildOptions) void {
    ///     gtk.bindTemplateChildPrivate(self, name, Private, Private.offset, options);
    /// }
    /// ```
    pub fn bindTemplateChildPrivate(
        class: *anyopaque,
        comptime name: [:0]const u8,
        comptime Private: type,
        private_offset: c_int,
        comptime options: gtk.ext.BindTemplateChildOptions,
    ) void {
        const field = options.field orelse name;
        const widget_class: *gtk.WidgetClass = @ptrCast(@alignCast(class));
        widget_class.bindTemplateChildFull(name, @intFromBool(options.internal), private_offset + @offsetOf(Private, field));
    }
};

/// Binds a field of the instance struct to an object declared in the
/// class template.
///
/// The name of the field in the instance struct defaults to the name of
/// the template object, but can be set explicitly via the `field` option
/// if it differs.
pub fn bindTemplateChild(class: anytype, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
    const field = options.field orelse name;
    gtk.WidgetClass.bindTemplateChildFull(class.as(gtk.WidgetClass), name, @intFromBool(options.internal), @offsetOf(@TypeOf(class).Instance, field));
}

pub const WidgetClass = struct {
    /// Sets the template for a widget from a byte slice.
    pub fn setTemplateFromSlice(class: *gtk.WidgetClass, template: [:0]const u8) void {
        var bytes = glib.ext.Bytes.newFromSlice(template);
        defer bytes.unref();
        class.setTemplate(bytes);
    }
};
