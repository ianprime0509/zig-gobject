#!/bin/sh
exec flatpak run --filesystem=home --share=network --share=ipc --socket=fallback-x11 --socket=wayland --device=dri --socket=session-bus org.gnome.Sdk//46