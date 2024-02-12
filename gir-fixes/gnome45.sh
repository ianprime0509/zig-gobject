#!/usr/bin/env sh
input_dir=${1?Missing input directory}
output_dir=${2?Missing output directory}

mkdir -p "$output_dir"

# GObject-2.0
xmlstarlet ed \
    `# https://github.com/ianprime0509/zig-gobject/issues/37` \
    --var TypeCValue '//_:union[@name="TypeCValue"]' \
    \
    --subnode '$TypeCValue' -t elem -n field \
    --var v_int '$prev' \
    --subnode '$v_int' -t attr -n name -v v_int \
    --subnode '$v_int' -t elem -n type \
    --var v_int_type '$prev' \
    --subnode '$v_int_type' -t attr -n name -v gint \
    --subnode '$v_int_type' -t attr -n c:type -v gint \
    \
    --subnode '$TypeCValue' -t elem -n field \
    --var v_long '$prev' \
    --subnode '$v_long' -t attr -n name -v v_long \
    --subnode '$v_long' -t elem -n type \
    --var v_long_type '$prev' \
    --subnode '$v_long_type' -t attr -n name -v glong \
    --subnode '$v_long_type' -t attr -n c:type -v glong \
    \
    --subnode '$TypeCValue' -t elem -n field \
    --var v_int64 '$prev' \
    --subnode '$v_int64' -t attr -n name -v v_int64 \
    --subnode '$v_int64' -t elem -n type \
    --var v_int64_type '$prev' \
    --subnode '$v_int64_type' -t attr -n name -v gint64 \
    --subnode '$v_int64_type' -t attr -n c:type -v gint64 \
    \
    --subnode '$TypeCValue' -t elem -n field \
    --var v_double '$prev' \
    --subnode '$v_double' -t attr -n name -v v_double \
    --subnode '$v_double' -t elem -n type \
    --var v_double_type '$prev' \
    --subnode '$v_double_type' -t attr -n name -v gdouble \
    --subnode '$v_double_type' -t attr -n c:type -v gdouble \
    \
    --subnode '$TypeCValue' -t elem -n field \
    --var v_pointer '$prev' \
    --subnode '$v_pointer' -t attr -n name -v v_pointer \
    --subnode '$v_pointer' -t elem -n type \
    --var v_pointer_type '$prev' \
    --subnode '$v_pointer_type' -t attr -n name -v gpointer \
    --subnode '$v_pointer_type' -t attr -n c:type -v gpointer \
    "$1"/GObject-2.0.gir >"$2"/GObject-2.0.gir
