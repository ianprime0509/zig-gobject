# zig-gobject

Early work-in-progress bindings for GObject-based libraries (such as GTK)
generated using GObject introspection data.

To generate the bindings, run the following command, substituting `Gtk-4.0` with
one or more libraries (with files residing under `lib/gir-files`). Bindings for
dependencies will be generated automatically, so it is not necessary to specify
GLib, GObject, etc. in this example.

```sh
zig build run -- lib/gir-files gir-extras src/gir-out Gtk-4.0
```

Then, run `zig build example-run` to run the example program. The example
program is a launcher for the various examples located under `src/examples`.
