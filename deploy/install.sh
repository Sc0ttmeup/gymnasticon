#!/bin/bash
set -e

echo "=== Starting Gymnasticon Installation ==="

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"
TMP_CLONE_DIR="/tmp/gymnasticon-clone"

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo apt-get remove -y nodejs nodejs-doc || true

# System updates and dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils

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

# Clone Gymnasticon
echo "Cloning Gymnasticon repository..."
rm -rf "$TMP_CLONE_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$TMP_CLONE_DIR"

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"
cp -R "$TMP_CLONE_DIR"/* "$INSTALL_DIR"
rm -rf "$TMP_CLONE_DIR"

# NPM configuration for RPi Zero
echo "Configuring npm for RPi Zero..."
export npm_config_build_from_source=true
export NODE_OPTIONS="--max-old-space-size=512"
npm config set unsafe-perm true
npm config set legacy-peer-deps true
npm set audit false

# Install dependencies
echo "Installing dependencies..."
cd "$INSTALL_DIR"
npm install --save-dev @babel/core @babel/cli @babel/preset-env

# Add Babel configuration
echo "Adding Babel configuration..."
cat > "$INSTALL_DIR/.babelrc" << 'EOF'
{
  "presets": ["@babel/preset-env"]
}
EOF

# Build process
echo "Building Gymnasticon..."
npm run build || { echo "Build failed. Check logs for details."; exit 1; }

# Create executable wrapper
echo "Creating executable wrapper..."
cat > "$INSTALL_DIR/lib/gymnasticon.js" << 'EOF'
#!/usr/bin/env node
require('./index.js');
EOF

# Set up binary path and executable
echo "Setting up binary path..."
sudo mkdir -p "$INSTALL_DIR/bin"
sudo ln -sf "$INSTALL_DIR/lib/gymnasticon.js" "$INSTALL_DIR/bin/gymnasticon"
sudo chmod +x "$INSTALL_DIR/lib/gymnasticon.js"
sudo chown -R pi:pi "$INSTALL_DIR"

# Service setup
echo "Setting up systemd service..."
sudo cp "$INSTALL_DIR/deploy/gymnasticon.service" /etc/systemd/system/
sudo sed -i "s|ExecStart=.*|ExecStart=/opt/gymnasticon/bin/gymnasticon|" /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Final verification
echo "Verifying service status..."
sudo systemctl status gymnasticon --no-pager

echo "=== Gymnasticon Installation Complete ==="
echo "You can check the service status with: sudo systemctl status gymnasticon"
