#!/bin/bash
set -e

# Create directories
mkdir -p libs
mkdir -p libs_temp

cd libs_temp

# Download packages (headers and binaries)
# We fetch dev packages for headers/.so symlinks and runtime packages for the actual libraries
echo "Downloading GEGL and Babl packages..."
apt-get download libgegl-dev libgegl-0.4-0t64 libbabl-dev libbabl-0.1-0

# Extract to libs directory
echo "Extracting... "
for f in *.deb; do
    echo "  $f"
    dpkg -x "$f" ../libs
done

cd ..
rm -rf libs_temp

echo "Done. Libraries installed in ./libs"
