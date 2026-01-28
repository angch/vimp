#!/bin/bash
set -e

# Directory to store the mirror
TARGET_DIR="ref/gnome-hig"
mkdir -p "$TARGET_DIR"

echo "Mirroring https://developer.gnome.org/hig/ into $TARGET_DIR..."

wget \
    --mirror \
    --convert-links \
    --adjust-extension \
    --page-requisites \
    --no-parent \
    --directory-prefix="$TARGET_DIR" \
    --no-host-directories \
    https://developer.gnome.org/hig/

echo "Mirroring complete. Content is available in $TARGET_DIR/hig/index.html"
