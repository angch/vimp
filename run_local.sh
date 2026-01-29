#!/bin/bash
export GEGL_PATH=$(pwd)/libs/usr/lib/x86_64-linux-gnu/gegl-0.4
export BABL_PATH=$(pwd)/libs/usr/lib/x86_64-linux-gnu/babl-0.1
export LD_LIBRARY_PATH=$(pwd)/libs/usr/lib/x86_64-linux-gnu
export DISPLAY=localhost:10

./zig-out/bin/vimp
