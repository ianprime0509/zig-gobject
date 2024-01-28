# zig-gobject

Early work-in-progress bindings for GObject-based libraries (such as GTK)
generated using GObject introspection data.

To generate all available bindings using the files under `lib/gir-files`, run
`zig build codegen`. This will generate bindings to the `bindings` directory,
which can be used as a dependency (using the Zig package manager) in other
projects.

To generate bindings only for a subset of available libraries, run the following
command, substituting `Gtk-4.0` with one or more libraries (with files residing
under `lib/gir-files`). Bindings for dependencies will be generated
automatically, so it is not necessary to specify GLib, GObject, etc. in this
example.

```sh
zig build run -- --gir-dir lib/gir-files --extras-dir extras --output-dir src/gir-out Gtk-4.0
```

## Usage

To use the bindings, add the `bindings` branch of this repository to
`build.zig.zon` and use the `addBindingModule` function exposed by `build.zig`:

```zig
// exe is the compilation step for your applicaton
exe.addModule("gtk", zig_gobject.addBindingModule(b, exe, "gtk-4.0"));
```

There are examples of this pattern in the `examples` and `test` subprojects.

## Examples

There are several examples in the `examples` directory, which is itself a
runnable project (depending on the `bindings` directory as a dependency). To
ensure the bindings are generated and run the example project launcher, run
`zig build run-example`.

## Binding philosophy

zig-gobject is fundamentally a low-level binding, with some higher-level
extensions provided within the `ext` namespace of each binding module.  The
bindings are a direct translation of information available in GIR (GObject
introspection repository) files, represented and organized in a way that makes
sense in Zig while maintaining transparency of the underlying symbols.
Basically, they can be thought of as an enhanced `zig translate-c`, using
GObject introspection for additional expressiveness (such as pointer
nullability).

For example, consider `gtk.Application.new` from the generated GTK 4 bindings,
which is translated as follows:

```zig
extern fn gtk_application_new(p_application_id: ?[*:0]const u8, p_flags: gio.ApplicationFlags) *_Self;
pub const new = gtk_application_new;
```

The `new` function here is merely an alias for the underlying
`gtk_application_new` function, which, thanks to the rich information provided
by GObject introspection, has a more useful signature than what
`zig translate-c` could have provided using the C headers, which would look like
the following:

```zig
extern fn gtk_application_new(application_id: [*c]const u8, flags: GApplicationFlags) [*c]GtkApplication;
```

The key difference here is the use of richer Zig pointer types rather than C
pointers, which offers greater safety. Another very useful translation
enrichment enabled by GObject introspection is in the `gio.ApplicationFlags`
type referenced here, which is translated as follows by zig-gobject:

```zig
/// Flags used to define the behaviour of a #GApplication.
pub const ApplicationFlags = packed struct(c_uint) {
    is_service: bool = false,
    is_launcher: bool = false,
    handles_open: bool = false,
    handles_command_line: bool = false,
    send_environment: bool = false,
    non_unique: bool = false,
    can_override_app_id: bool = false,
    allow_replacement: bool = false,
    replace: bool = false,
    // Padding fields omitted

    const flags_none: ApplicationFlags = @bitCast(@as(c_uint, 0));
    const default_flags: ApplicationFlags = @bitCast(@as(c_uint, 0));
    const is_service: ApplicationFlags = @bitCast(@as(c_uint, 1));
    const is_launcher: ApplicationFlags = @bitCast(@as(c_uint, 2));
    const handles_open: ApplicationFlags = @bitCast(@as(c_uint, 4));
    const handles_command_line: ApplicationFlags = @bitCast(@as(c_uint, 8));
    const send_environment: ApplicationFlags = @bitCast(@as(c_uint, 16));
    const non_unique: ApplicationFlags = @bitCast(@as(c_uint, 32));
    const can_override_app_id: ApplicationFlags = @bitCast(@as(c_uint, 64));
    const allow_replacement: ApplicationFlags = @bitCast(@as(c_uint, 128));
    const replace: ApplicationFlags = @bitCast(@as(c_uint, 256));
    extern fn g_application_flags_get_type() usize;
    pub const getGObjectType = g_application_flags_get_type;
};
```

The use of `packed struct` here is a more idiomatic pattern in Zig for flags,
allowing us to write code such as this:

```zig
const app = gtk.Application.new("com.example.Example", .{ .handles_open = true });
```

The translation offered by `zig translate-c`, on the other hand, is much more
basic:

```zig
pub const GApplicationFlags = c_uint;
```

The generated bindings also include some core-level helpers such as `connect*`
methods for type-safe signal connection.

The extensions available within the `ext` namespace of each binding package are
written by hand and copied from the `extensions` directory of the project. They
provide higher-level helper functions which are not translated from GIR, such as
`gobject.defineType` to define a new class type in the GObject type system.
