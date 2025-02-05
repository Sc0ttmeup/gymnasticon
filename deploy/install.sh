#!/bin/bash
# File: C:\gymnasticon\deploy\install.sh
# Description: Installation script for Gymnasticon on an RPiZero with Node 14.
# This version forces Babel to transpile ES module syntax to CommonJS using inline configuration,
# so that the built code in lib/ uses require() instead of import statements.

set -e

echo "=== Starting Gymnasticon Installation ==="

# Configuration variables
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"
TMP_CLONE_DIR="/tmp/gymnasticon-clone"

# Environment options for low-memory devices
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo apt-get remove -y nodejs nodejs-doc || true

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils

# Node.js installation for ARMv6 (RPiZero)
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Verify Node.js installation
echo "Verifying Node.js installation..."
node -v
npm -v

# Clone Gymnasticon repository
echo "Cloning Gymnasticon repository..."
rm -rf "$TMP_CLONE_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$TMP_CLONE_DIR"

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"
cp -R "$TMP_CLONE_DIR"/* "$INSTALL_DIR"
rm -rf "$TMP_CLONE_DIR"

# NPM configuration
echo "Configuring npm..."
cd "$INSTALL_DIR"
npm config set unsafe-perm true
npm config set legacy-peer-deps true
npm config set audit false

# Install dependencies (including devDependencies)
echo "Installing dependencies..."
npm install

# Build process using inline Babel configuration to force CommonJS transformation.
# This bypasses any .babelrc that might be causing ES module output.
echo "Building Gymnasticon with inline Babel config..."
npx babel src --no-babelrc --presets=@babel/preset-env --plugins=@babel/plugin-transform-modules-commonjs --targets="node 14" --delete-dir-on-start -d lib

# Create executable wrapper
echo "Creating executable wrapper..."
mkdir -p "$INSTALL_DIR/node/bin"
cat > "$INSTALL_DIR/node/bin/gymnasticon" << 'EOF'
#!/usr/bin/node
require('../../lib/app/cli.js');
EOF

# Set wrapper permissions and ownership
echo "Setting up permissions..."
sudo chmod +x "$INSTALL_DIR/node/bin/gymnasticon"
sudo chown -R pi:pi "$INSTALL_DIR"

# Service setup
echo "Setting up systemd service..."
sudo cp "$INSTALL_DIR/deploy/gymnasticon.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Final verification of service status
echo "Verifying service status..."
sudo systemctl status gymnasticon --no-pager

echo "=== Gymnasticon Installation Complete ==="
echo "You can check the service status with: sudo systemctl status gymnasticon"
