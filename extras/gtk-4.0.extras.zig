const glib = @import("glib-2.0");

pub fn WidgetClassMethods(comptime Self: type) type {
    return struct {
        pub const BindTemplateChildOptions = struct {
            field: ?[]const u8 = null,
            private: bool = false,
            internal: bool = false,
        };

        /// Binds a field of the instance struct to an object declared in the class template.
        ///
        /// The name of the field in the instance struct defaults to the name of the template object, but can be set explicitly via the `field` option if it differs.
        pub fn bindTemplateChild(class: *Self, comptime name: [:0]const u8, comptime options: BindTemplateChildOptions) void {
            const field = options.field orelse name;
            const offset = if (options.private) Self.Instance.offsetOfPrivate(field) else @offsetOf(Self.Instance, field);
            class.bindTemplateChildFull(name, @boolToInt(options.internal), offset);
        }

        /// Sets the template for a widget from a byte slice.
        pub fn setTemplateFromSlice(class: *Self, template: [:0]const u8) void {
            var bytes = glib.Bytes.newFromSlice(template);
            defer bytes.unref();
            class.setTemplate(bytes);
        }
    };
}
