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

## Required Zig version

This project relies heavily on the in-progress Zig package manager to structure
itself into various submodules. As the Zig package manager is not yet complete,
building this project requires a build of the latest Zig master branch with the
following additional changes applied:

- https://github.com/ziglang/zig/pull/14603 - to support dependencies specified
  as paths
- https://github.com/ziglang/zig/pull/14731 - to support additional `Module`
  APIs
- The following small patch to avoid needing to specify a `hash` for each
  submodule (see
  https://github.com/ziglang/zig/issues/14339#issuecomment-1474518628):
  ```patch
  --- a/src/Package.zig
  +++ b/src/Package.zig
  @@ -746,7 +746,7 @@ fn fetchAndUnpack(
                  h, actual_hex,
              });
          }
  -    } else {
  +    } else if (dep.location != .path) {
          const file_path = try report.directory.join(gpa, &.{Manifest.basename});
          defer gpa.free(file_path);

  ```
