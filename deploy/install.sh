#!/bin/bash
# File: install.sh
# Location: repository root
# This script installs Gymnasticon on a Raspberry Pi Zero running Node 14
# It includes fixes for the node-usb build on low‑power devices and ensures Bluetooth LE is enabled.

set -e

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"

# Environment setup
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*

# Force single-threaded make to avoid build issues on low-power hardware
export MAKEFLAGS=-j1

# System preparation
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Verify Node.js installation
node -v
npm -v

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo rm -rf "$INSTALL_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
cd "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"

# NPM setup (using the pi user)
sudo -u pi npm config set unsafe-perm true
sudo -u pi npm config set legacy-peer-deps true
sudo -u pi npm config set audit false

# Install dependencies
echo "Installing npm dependencies..."
sudo -u pi npm install --save-dev @babel/core @babel/cli @babel/preset-env
sudo -u pi npm install --production

# Configure Babel
cat > .babelrc << 'EOF'
{
  "presets": [
    ["@babel/preset-env", {
      "targets": {
        "node": "14"
      },
      "modules": "commonjs"
    }]
  ]
}
EOF

# Build step (transpile source code)
sudo -u pi ./node_modules/.bin/babel src -d dist --copy-files

# Bluetooth configuration for LE broadcasting
echo "Configuring Bluetooth for LE broadcasting..."
sudo usermod -a -G bluetooth pi
sudo setcap cap_net_raw+eip $(eval readlink -f $(which node))
# Power on Bluetooth, set LE mode, and bring up the interface with advertising enabled
sudo btmgmt power on
sudo btmgmt le on
sudo hciconfig hci0 up
sudo hciconfig hci0 leadv

# Ensure BlueZ uses LE mode by updating the main config file
echo "[General]
ControllerMode = le
" | sudo tee /etc/bluetooth/main.conf

# Restart Bluetooth service to load changes
sudo systemctl enable bluetooth
sudo systemctl restart bluetooth
sleep 5

# Create systemd service file for Gymnasticon
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth.service network.target
Wants=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/node $INSTALL_DIR/dist/app/cli.js
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=10
User=pi
Group=pi
Environment=NODE_ENV=production
Environment=DEBUG=gym:*
Environment=NOBLE_HCI_DEVICE_ID=hci0
Environment=BLENO_HCI_DEVICE_ID=hci0
Environment=NOBLE_MULTI_ROLE=1
SyslogIdentifier=gymnasticon

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions for the service file
sudo chown root:root /etc/systemd/system/gymnasticon.service
sudo chmod 644 /etc/systemd/system/gymnasticon.service

# Start the Gymnasticon service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete. Check status with: sudo systemctl status gymnasticon"
