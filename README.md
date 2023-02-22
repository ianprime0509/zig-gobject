# zig-gobject

Early work-in-progress bindings for GObject-based libraries (such as GTK)
generated using GObject introspection data.

To generate all available bindings using the files under `lib/gir-files`, run
`zig build codegen`.

To generate bindings only for a subset of available libraries, run the following
command, substituting `Gtk-4.0` with one or more libraries (with files residing
under `lib/gir-files`). Bindings for dependencies will be generated
automatically, so it is not necessary to specify GLib, GObject, etc. in this
example.

```sh
zig build run -- lib/gir-files gir-extras src/gir-out Gtk-4.0
```

## Examples

Several examples are located under `src/examples`. The `example.zig` program
acts as a launcher for the examples, and can be run using `zig build
example-run` (which will also trigger codegen, since the examples rely on the
generated libraries).
