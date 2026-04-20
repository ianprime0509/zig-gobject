#!/bin/sh
opts=$(getopt -o '' -l host-filesystem -n "$0" -- "$@")
[[ $? -ne 0 ]] && exit 1
eval set -- "$opts"

filesystem_option="--filesystem=home"
while true; do
  case "$1" in
    --host-filesystem) filesystem_option="--filesystem=host"; shift ;;
    --) shift; break ;;
    *) exit 1 ;;
  esac
done

sdk_version=${1:-49}
exec flatpak run $filesystem_option --share=network --share=ipc --socket=fallback-x11 --socket=wayland --device=dri --socket=session-bus org.gnome.Sdk//$sdk_version
