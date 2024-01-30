# Binding strategy

Most of the bindings generated by zig-gobject are direct translations of the
source GIR (GObject introspection metadata), adjusted to better fit Zig
conventions (such as `camelCase` function names). For example, the function
`gtk_application_new` is translated to `gtk.Application.new`. However, there are
some additional elements added by the translation process to expose metadata
(such as type inheritance) and make common tasks simpler and safer.

The generated bindings are designed to provide direct transparency to the
underlying library functions. For example, consider the source of
`gtk.Application.new`:

```zig
extern fn gtk_application_new(p_application_id: ?[*:0]const u8, p_flags: gio.ApplicationFlags) *_Self;
pub const new = gtk_application_new;
```

The generated binding here is really a _binding_ rather than a _wrapper_: the
function `gtk.Application.new` is exactly the same as `gtk_application_new` at
the binary level. This is similar to the philosophy behind `zig translate-c`,
but the GIR data offers much greater organization and precision in the result,
such as the use of the correct pointer type `?[*:0]const u8` for the application
ID, rather than the limited `[*c]const u8` which `zig translate-c` would
produce.

## Usage conventions

While it is possible for functions in Zig to be called using method call syntax
`obj.method()` if `method` has the type of `obj` as its first parameter, most
methods in this library are conventionally called with the more verbose syntax
`Obj.method(obj)`. The primary reason for this is visual consistency between
normal methods, type-safe generated helpers, and extensions:

- `gtk.Widget.show(win.as(gtk.Widget))`
- `gtk.Button.connectClicked(button, Data, &handleButtonClicked, data, .{})`
- `gtk.ext.WidgetClass.setTemplateFromSlice(class.as(gtk.Widget.Class), template)`

It is also hoped that [the `@Result` builtin
proposal](https://github.com/ziglang/zig/issues/16313) will be accepted, which
would allow the elimination of redundant information from the `as` calls.

It is up to the user to decide when to use this more verbose method call syntax
or the shorter `obj.method()` syntax. There are cases where the above reasoning
doesn't apply, and using the shorter syntax is desirable: for example, when
working with Cairo types, which don't have signal handlers or other helpers, it
is much nicer to write `cr.moveTo(0, 0)` than `cairo.Context.moveTo(cr, 0, 0)`.

## Extensions

Most additional functionality provided by zig-gobject on top of the libraries
being bound is added through _extensions_. These extensions are not added
directly to the generated bindings; rather, the extensions file for a namespace
is exposed as `ext` from the bindings for the namespace. For example, the
extensions for GObject can be accessed through `gobject.ext`.

It is conventional for the extensions of a namespace to mirror the structure of
the namespace being extended. For example, the function
`glib.ext.Bytes.newFromSlice` is a helper function which creates a `glib.Bytes`
from a slice of bytes.

## Type system metadata

GObject is built around an [object-oriented type
system](https://docs.gtk.org/gobject/concepts.html). zig-gobject exposes
metadata about relationships in the type system through a few special members:

- `fn getGObjectType() gobject.Type` - this is the GObject "get-type" function
  for a type, returning the registered `gobject.Type` for the type. For example,
  the C macro `GTK_TYPE_APPLICATION` can be expressed as
  `gtk.Application.getGObjectType()` in Zig.
- `const Class: type` - for a class type, this is the associated class struct.
  For example, `GObjectClass` in C is equivalent to `gobject.Object.Class` in
  Zig.
- `const Iface: type` - for an interface type, this is the associated interface
  struct.
- `const Parent: type` - for a class type, this is the parent type. For example,
  `gtk.ApplicationWindow.Parent` is the same as `gtk.Window`.
- `const Implements: [_]type` - for a class type, this is an array of all the
  interface types implemented by the class. For example, `gtk.Window.Implements`
  contains several types, including `gtk.Buildable`.
- `const Prerequisites: [_]type` - for an interface type, this is an array of all
  the prerequisite types of the interface.

As an example of how these additional members are useful, the function
`gobject.ext.as` casts an object instance to another type, failing to compile if
the correctness of the cast cannot be guaranteed. For example, if `win` is a
`gtk.Window`, then the call `gobject.ext.as(gobject.Object, win)` works, but
`gobject.ext.as(gtk.ApplicationWindow, win)` will fail to compile, because `win`
might not be an instance of `gtk.ApplicationWindow`.

## Signal handlers

Each signal associated with a type leads to a `connectSignal` function being
generated on the type with the following signature:

```zig
fn connectSignal(
    /// The object to which to connect the signal handler.
    obj: anytype,
    /// The type of the user data to pass to the handler.
    comptime T: type,
    /// The signal handler function.
    callback: *const fn (@TypeOf(obj), ...signal parameters..., T),
    /// User data to pass to the handler.
    data: T,
    /// Signal connection options.
    options: struct { after: bool = false },
)
```

Using these generated signal connection functions offers greater type safety
than calling `gobject.signalConnectData` directly.

## Virtual method implementations

Each virtual method associated with a class leads to an `implementMethod`
function being generated on the corresponding type struct type with the
following signature:

```zig
fn implementMethod(
    /// The type struct instance on which to implement the method.
    class: anytype,
    /// The implementation of the method.
    impl: *const fn(*@typeInfo(@TypeOf(class)).Pointer.child.Instance, ...method parameters...) ...method return type...,
)
```

For example, the virtual method `finalize` can be implemented for an object type
using `gobject.Object.Class.implementFinalize`. This offers greater type safety
than casting the type struct instance to an ancestor type and setting the method
field directly.

## Utility functions

Some utility functions are added to the generated types to improve the safety
and ease of use of the bindings. These utility functions are chosen judiciously:
most additional utility functions are available through extensions rather than
translated directly into the bindings, to avoid confusion and collision with the
rest of the translated bindings.

- `fn as(self: *Self, comptime T: type) *T` - for a class, interface, or type
  struct type, this is a shortcut for `gobject.ext.as`, due to its extremely
  frequent use.
- `fn ref(self: *Self) void` - for a type with a reference function defined in
  its GIR, or for a type known to extend from `gobject.Object`, this is a
  function used to increment the object's reference count. This is generated
  only if the containing type does not already have a member translated as
  `ref`.
- `fn unref(self: *Self) void` - like `ref`, but decrements the object's
  reference count.