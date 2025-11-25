#!/bin/bash
# Run commands from stdin in a GNOME SDK Flatpak with Zig in the path.
set -euo pipefail
sdk_version=${1:?missing GNOME SDK version}
zig_bin_dir=$(dirname "$(command -v zig)")

tmp_dir=$(mktemp -d)
script_path="$tmp_dir"/script.sh
echo "PATH=$zig_bin_dir:\$PATH" >"$script_path"
cat >>"$script_path"
chmod +x "$script_path"

exec flatpak run \
  --filesystem="$PWD" \
  --filesystem="$tmp_dir" \
  --filesystem="$zig_bin_dir":ro \
  --share=network \
  --share=ipc \
  --socket=fallback-x11 \
  --socket=wayland \
  --device=dri \
  --socket=session-bus \
  --cwd="$PWD" \
  --command="$script_path" \
  org.gnome.Sdk//"$sdk_version"
