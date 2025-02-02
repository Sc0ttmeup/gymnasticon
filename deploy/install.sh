#!/bin/bash
set -e

echo "=== Starting Gymnasticon Installation ==="

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo apt-get remove -y nodejs nodejs-doc || true

# System updates and dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    git \
    bluetooth \
    bluez \
    libbluetooth-dev \
    libudev-dev \
    libusb-1.0-0-dev \
    build-essential \
    curl \
    xz-utils

# Node.js installation
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
# Install Gymnasticon with proper permissions
echo "Installing Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"  # Set correct ownership
cd "$INSTALL_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git .
# NPM configuration for RPi Zero
echo "Configuring npm for RPi Zero..."
export npm_config_build_from_source=true
export NODE_OPTIONS="--max-old-space-size=128"
npm config set unsafe-perm true
npm config set legacy-peer-deps true

# Build process
echo "Building Gymnasticon..."
npm install
npm run build

# Service setup
echo "Setting up systemd service..."
sudo cp deploy/gymnasticon.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Final verification
echo "Verifying service status..."
sudo systemctl status gymnasticon --no-pager

echo "=== Gymnasticon Installation Complete ==="
echo "You can check the service status with: sudo systemctl status gymnasticon"
