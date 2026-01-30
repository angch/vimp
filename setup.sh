#!/bin/bash
set -e

echo "=========================================="
echo " Vimp Environment Setup"
echo "=========================================="

# Detect sudo
SUDO=""
if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: This script requires root privileges or sudo access to install packages."
        exit 1
    fi
fi

# 1. Install System Dependencies
echo "[1/4] Installing system dependencies..."
$SUDO apt-get update
$SUDO apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    pkg-config \
    xz-utils \
    meson \
    ninja-build \
    libgtk-4-dev \
    libgtk-4-1 \
    libadwaita-1-dev \
    libgegl-dev \
    libbabl-dev

# 2. Install Zig
echo ""
echo "[2/4] Installing Zig 0.15.2..."
ZIG_VERSION="0.15.2"
ZIG_ARCH_OS="x86_64-linux"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH_OS}-${ZIG_VERSION}.tar.xz"
ZIG_INSTALL_DIR="${HOME}/.local/zig"
ZIG_DIR_NAME="zig-${ZIG_ARCH_OS}-${ZIG_VERSION}"
ZIG_BIN_PATH="${ZIG_INSTALL_DIR}/${ZIG_DIR_NAME}"

if [ ! -d "${ZIG_BIN_PATH}" ]; then
    mkdir -p "${ZIG_INSTALL_DIR}"
    echo "  Downloading Zig from ${ZIG_URL}..."
    curl -L -o "/tmp/zig.tar.xz" "${ZIG_URL}"
    echo "  Extracting..."
    tar -xf "/tmp/zig.tar.xz" -C "${ZIG_INSTALL_DIR}"
    rm "/tmp/zig.tar.xz"
    echo "  Installed to ${ZIG_BIN_PATH}"
else
    echo "  Zig already installed at ${ZIG_BIN_PATH}"
fi

# Add to PATH for future sessions
if ! grep -q "${ZIG_BIN_PATH}" "${HOME}/.bashrc"; then
    echo "" >> "${HOME}/.bashrc"
    echo "# Zig compiler" >> "${HOME}/.bashrc"
    echo "export PATH=\"${ZIG_BIN_PATH}:\$PATH\"" >> "${HOME}/.bashrc"
    echo "  Added Zig to PATH in ~/.bashrc"
fi

# Add to PATH for current execution
export PATH="${ZIG_BIN_PATH}:$PATH"

# 3. Setup Vendored Libraries
echo ""
echo "[3/4] Setting up vendored libraries..."
if [ -f "scripts/setup_libs.sh" ]; then
    bash scripts/setup_libs.sh
else
    echo "  Error: scripts/setup_libs.sh not found!"
    exit 1
fi

# 3.5 Setup Reference GIMP (needed for tests)
echo ""
echo "[3.5/4] Setting up reference GIMP repository..."
mkdir -p ref
if [ ! -d "ref/gimp" ]; then
    echo "  Cloning GIMP repository to ref/gimp..."
    git clone --depth 1 https://github.com/GNOME/gimp.git ref/gimp
else
    echo "  Reference GIMP directory already exists."
fi

# 4. Verify Setup
echo ""
echo "[4/4] Verifying setup..."
if command -v zig >/dev/null 2>&1; then
    echo "  Zig version: $(zig version)"
else
    echo "  Error: Zig is not in PATH."
    exit 1
fi

echo ""
echo "=========================================="
echo " Setup Complete!"
echo "=========================================="
echo "Run 'source ~/.bashrc' to update your current shell,"
echo "or just run 'make build' immediately."
