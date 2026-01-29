#!/bin/bash
#
# Vimp Development Environment Setup Script
# Target: Ubuntu 24.04 Desktop (amd64)
#
# This script sets up a fresh Ubuntu 24.04 machine for Vimp development.
# Run with: bash scripts/setup_dev_machine.sh
#

set -e

echo "=========================================="
echo " Vimp Development Environment Setup"
echo " Target: Ubuntu 24.04 Desktop (amd64)"
echo "=========================================="
echo ""

# Configuration
ZIG_VERSION="0.15.2"
ZIG_ARCH_OS="x86_64-linux"
PROJECT_REPO="git@github.com:angch/vimp.git"
PROJECT_DIR="${HOME}/project/vimp"

# -----------------------------------------------------------------------------
# Step 1: Update system packages
# -----------------------------------------------------------------------------
echo "[1/6] Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# -----------------------------------------------------------------------------
# Step 2: Install essential build tools
# -----------------------------------------------------------------------------
echo ""
echo "[2/6] Installing essential build tools..."
sudo apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    pkg-config \
    xz-utils

# -----------------------------------------------------------------------------
# Step 3: Install GTK4 development libraries
# -----------------------------------------------------------------------------
echo ""
echo "[3/6] Installing GTK4 development libraries..."
sudo apt-get install -y \
    libgtk-4-dev \
    libgtk-4-1 \
    libadwaita-1-dev

# -----------------------------------------------------------------------------
# Step 4: Install GEGL and Babl development libraries
# -----------------------------------------------------------------------------
echo ""
echo "[4/6] Installing GEGL and Babl development libraries..."
sudo apt-get install -y \
    libgegl-dev \
    libgegl-0.4-0t64 \
    libbabl-dev \
    libbabl-0.1-0

# -----------------------------------------------------------------------------
# Step 5: Install Zig compiler
# -----------------------------------------------------------------------------
echo ""
echo "[5/6] Installing Zig ${ZIG_VERSION}..."

ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH_OS}-${ZIG_VERSION}.tar.xz"
ZIG_INSTALL_DIR="${HOME}/.local/zig"
ZIG_DIR_NAME="zig-${ZIG_ARCH_OS}-${ZIG_VERSION}"

# Create installation directory
mkdir -p "${ZIG_INSTALL_DIR}"

# Download and extract Zig
if [ ! -f "${ZIG_INSTALL_DIR}/${ZIG_DIR_NAME}/zig" ]; then
    echo "  Downloading Zig from ${ZIG_URL}..."
    curl -L -o "/tmp/zig.tar.xz" "${ZIG_URL}"
    tar -xf "/tmp/zig.tar.xz" -C "${ZIG_INSTALL_DIR}"
    rm "/tmp/zig.tar.xz"
    echo "  Zig ${ZIG_VERSION} installed to ${ZIG_INSTALL_DIR}/${ZIG_DIR_NAME}"
else
    echo "  Zig ${ZIG_VERSION} already installed."
fi

# Add Zig to PATH if not already there
ZIG_BIN_PATH="${ZIG_INSTALL_DIR}/${ZIG_DIR_NAME}"
if ! grep -q "${ZIG_BIN_PATH}" "${HOME}/.bashrc" 2>/dev/null; then
    echo "" >> "${HOME}/.bashrc"
    echo "# Zig compiler" >> "${HOME}/.bashrc"
    echo "export PATH=\"${ZIG_BIN_PATH}:\$PATH\"" >> "${HOME}/.bashrc"
    echo "  Added Zig to PATH in ~/.bashrc"
fi

# Export for current session
export PATH="${ZIG_BIN_PATH}:$PATH"

# -----------------------------------------------------------------------------
# Step 6: Clone project repository (optional)
# -----------------------------------------------------------------------------
echo ""
echo "[6/6] Setting up project repository..."

if [ -d "${PROJECT_DIR}" ]; then
    echo "  Project directory already exists at ${PROJECT_DIR}"
    echo "  Skipping clone."
else
    echo "  Cloning repository..."
    mkdir -p "$(dirname ${PROJECT_DIR})"
    git clone "${PROJECT_REPO}" "${PROJECT_DIR}"
fi

# -----------------------------------------------------------------------------
# Post-setup
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo " Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Reload your shell or run: source ~/.bashrc"
echo ""
echo "  2. Navigate to project directory:"
echo "     cd ${PROJECT_DIR}"
echo ""
echo "  3. Setup vendored libs (optional, for GEGL/Babl headers):"
echo "     bash tools/setup_libs.sh"
echo ""
echo "  4. Build the project:"
echo "     zig build"
echo ""
echo "  5. Run the application:"
echo "     zig build run"
echo ""
echo "Installed versions:"
echo "  Zig:  $(${ZIG_BIN_PATH}/zig version)"
echo "  GTK4: $(pkg-config --modversion gtk4)"
echo "  GEGL: $(pkg-config --modversion gegl-0.4 2>/dev/null || echo 'available')"
echo "  Babl: $(pkg-config --modversion babl-0.1 2>/dev/null || echo 'available')"
echo ""
