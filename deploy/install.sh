#!/bin/bash
# File: deploy/install.sh
# Folder: deploy/
# Description: Installation script for Gymnasticon on Raspberry Pi Zero with Node.js 14.
# This script has been updated to work better on low-memory devices by ensuring that the
# proper user environment is used (with sudo -H) and by adding short delays after swap restarts.
# Security is not a concern per your note.

set -euo pipefail

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"

# Ensure the script is not run from inside the installation directory
if [ "$PWD" = "$INSTALL_DIR" ]; then
    echo "Current directory is $INSTALL_DIR. Changing to home directory to avoid conflicts..."
    cd ~
fi

# Environment setup
# Increase memory for Node if needed; adjust if you still run into memory issues.
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*
export MAKEFLAGS=-j1

# System checks and dependencies
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo "This script must be run on a Raspberry Pi"
    exit 1
fi

if ! command -v hciconfig >/dev/null 2>&1 || ! hciconfig | grep -q "hci0"; then
    echo "No Bluetooth adapter (hci0) found"
    exit 1
fi

# System preparation
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils dphys-swapfile

# Clean existing installation
echo "Cleaning up any existing installation..."
sudo systemctl stop gymnasticon || true
sudo systemctl disable gymnasticon || true
sudo rm -f /var/log/gymnasticon.log
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Increase swap for build
echo "Configuring swap space..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart
sleep 5  # allow swap changes to take effect

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
sudo tar -C /usr/local/ --strip-components=1 -xf "${NODE_DISTRO}.tar.xz"
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Clone and prepare Gymnasticon
echo "Installing Gymnasticon..."
sudo git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"

# Build process
cd "$INSTALL_DIR"
echo "Setting up NPM configuration..."
sudo -H -u pi npm config set unsafe-perm true
sudo -H -u pi npm config set legacy-peer-deps true
sudo -H -u pi npm config set audit false
sudo -H -u pi npm config set fund false
sudo -H -u pi npm config set update-notifier false

echo "Cleaning npm cache and removing old node_modules..."
sudo rm -rf node_modules
sudo -H -u pi npm cache clean --force

echo "Installing dependencies..."
npm install --no-optional --unsafe-perm --build-from-source



echo "Installing Bluetooth HCI socket dependency..."
sudo -H -u pi npm install @abandonware/bluetooth-hci-socket --unsafe-perm

echo "Building project..."
sudo -H -u pi npm run build

# Verify build success
if [ ! -f "$INSTALL_DIR/lib/app/cli.js" ]; then
    echo "Build failed - cli.js not found"
    exit 1
fi

# Restore swap
echo "Restoring swap configuration..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=100/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart
sleep 3

# Service setup
echo "Installing service files..."
sudo cp "${INSTALL_DIR}/deploy/gymnasticon.service" /etc/systemd/system/

# Configure Bluetooth
cat <<'EOF' | sudo tee /etc/bluetooth/main.conf
[General]
ControllerMode = le
EOF

sudo hciconfig hci0 down
sudo hciconfig hci0 up
sudo btmgmt le on
sudo bluetoothctl system-alias 'Gymnasticon2'

# Configure USB permissions and groups
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1009", MODE="0666"' | sudo tee /etc/udev/rules.d/99-garmin.rules
sudo usermod -a -G plugdev,bluetooth pi
sudo udevadm control --reload-rules
sudo setcap cap_net_raw,cap_net_admin+eip "$(readlink -f $(which node))"

# System optimizations
cat <<EOF | sudo tee /etc/sysctl.d/99-bluetooth.conf
kernel.sched_rt_runtime_us = 998000
EOF

# Log rotation
cat <<EOF | sudo tee /etc/logrotate.d/gymnasticon
/var/log/gymnasticon.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable bluetooth gymnasticon
sudo systemctl start bluetooth
sleep 5

# Verify build path before starting service
if [ -f "$INSTALL_DIR/lib/app/cli.js" ]; then
    sudo systemctl start gymnasticon
    sleep 10
    if systemctl is-active --quiet gymnasticon; then
        echo "Gymnasticon is running successfully."
    else
        echo "Gymnasticon failed to start. Check logs with: journalctl -u gymnasticon"
        exit 1
    fi
else
    echo "Required files missing. Installation failed."
    exit 1
fi

echo "Installation complete. Check service status with: sudo systemctl status gymnasticon"
