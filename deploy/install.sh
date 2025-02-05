#!/bin/bash
# File: C:\gymnasticon\deploy\install.sh
# Description: Installation script for Gymnasticon on an RPiZero with Node 14.
# This version creates a temporary Babel configuration file so that ES module syntax is
# transpiled to CommonJS (using require()) and then patches the systemd service to run
# Gymnasticon in bot (simulation) mode.
#
# If you have a real bike/Bluetooth adapter and do not want bot mode,
# simply remove or comment out the sed command near the end.

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

# Create a temporary Babel configuration file (placed in $INSTALL_DIR)
echo "Creating temporary Babel configuration file..."
cat > "$INSTALL_DIR/temp.babel.config.json" << 'EOF'
{
  "presets": [
    [
      "@babel/preset-env",
      {
        "targets": { "node": "14" },
        "modules": "commonjs"
      }
    ]
  ]
}
EOF

# Build process using the temporary Babel configuration file.
echo "Building Gymnasticon with temporary Babel config..."
npx babel src --config-file "$INSTALL_DIR/temp.babel.config.json" --delete-dir-on-start -d lib

# Remove the temporary Babel configuration file
rm "$INSTALL_DIR/temp.babel.config.json"

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

# (Optional) Patch the service ExecStart to use bot mode.
# Remove or comment out the following line if you wish to run with a real bike.
# sudo sed -i 's|ExecStart=/opt/gymnasticon/node/bin/gymnasticon|ExecStart=/opt/gymnasticon/node/bin/gymnasticon --bike bot|g' /etc/systemd/system/gymnasticon.service

sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Final verification of service status
echo "Verifying service status..."
sudo systemctl status gymnasticon --no-pager

echo "=== Gymnasticon Installation Complete ==="
echo "You can check the service status with: sudo systemctl status gymnasticon"
