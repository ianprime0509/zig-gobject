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
zig build run -- lib/gir-files gir-extras src/gir-out Gtk-4.0
```

## Examples

There are several examples in the `examples` directory, which is itself a
runnable project (depending on the `bindings` directory as a dependency). To
ensure the bindings are generated and run the example project launcher, run `zig
build run-example`.
