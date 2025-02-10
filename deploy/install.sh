#!/bin/bash
# File: deploy/install.sh
# Location: repository deploy folder
# Description: Installs Gymnasticon on a Raspberry Pi Zero with Node.js 14,
# initializes the Bluetooth adapter with retry logic, applies system optimizations,
# sets up log rotation, and configures systemd services.
#
# Note: This version uses the existing .babelrc in the repository root and assumes
# the repository structure is as follows:
#   <repo-root>/
#       .babelrc
#       src/
#       deploy/install.sh
#
# It also sets AmbientCapabilities in the Gymnasticon service so that the Node.js binary,
# which has been given cap_net_raw and cap_net_admin via setcap, can access Bluetooth
# without running as root.
#
# Usage: Run this script via ssh on your Raspberry Pi Zero.
set -e

# ------------------------------------------------------
# Configuration and Environment Variables
# ------------------------------------------------------
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"  # installation folder (repository root)

export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*
export MAKEFLAGS=-j1

# ------------------------------------------------------
# Pre-installation Checks
# ------------------------------------------------------
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo "This script must be run on a Raspberry Pi"
    exit 1
fi

if ! hciconfig | grep -q "hci0"; then
    echo "No Bluetooth adapter (hci0) found"
    exit 1
fi

# ------------------------------------------------------
# System Preparation and Swap Setup
# ------------------------------------------------------
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils dphys-swapfile jq

# Increase swap size temporarily
echo "Configuring swap space..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart

# ------------------------------------------------------
# Node.js Installation
# ------------------------------------------------------
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
sudo tar -C /usr/local/ --strip-components=1 -xf "${NODE_DISTRO}.tar.xz"
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# ------------------------------------------------------
# Gymnasticon Installation
# ------------------------------------------------------
echo "Installing Gymnasticon..."
sudo rm -rf "$INSTALL_DIR"
# Use sudo for the clone so that /opt/gymnasticon is created even if 'pi' lacks write permission
sudo git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"

# ------------------------------------------------------
# NPM Configuration and Build
# ------------------------------------------------------
cd "$INSTALL_DIR"
sudo -u pi npm config set unsafe-perm true
sudo -u pi npm config set legacy-peer-deps true
sudo -u pi npm config set audit false
sudo -u pi npm config set fund false
sudo -u pi npm config set update-notifier false

# Install Babel dependencies
echo "Installing Babel dependencies..."
if ! sudo -u pi npm install --save-dev @babel/core @babel/cli @babel/preset-env; then
    echo "Failed to install Babel dependencies"
    exit 1
fi

echo "Installing production dependencies in chunks..."
# Create a temporary package.json chunk file with minimal dependencies
sudo -u pi node -e "
    const pkg = require('./package.json');
    const deps = pkg.dependencies;
    const chunks = {};
    let i = 0;
    for (const [key, value] of Object.entries(deps)) {
        const chunkIndex = Math.floor(i++ / 5);
        chunks[chunkIndex] = chunks[chunkIndex] || {};
        chunks[chunkIndex][key] = value;
    }
    require('fs').writeFileSync('chunks.json', JSON.stringify(chunks, null, 2));
"

# Install dependencies in chunks
for chunk in $(jq -r 'keys | .[]' chunks.json); do
    echo "Installing dependency chunk $chunk..."
    deps=$(jq -r ".[$chunk]" chunks.json)
    if ! sudo -u pi npm install --no-save $(echo "$deps" | jq -r 'to_entries | map("\(.key)@\(.value)") | .[]'); then
        echo "Failed to install dependency chunk $chunk"
        exit 1
    fi
    # Clear npm cache after each chunk (run as pi)
    sudo -u pi npm cache clean --force
done

# Cleanup temporary files
rm chunks.json

# ------------------------------------------------------
# Build Step with Error Handling
# ------------------------------------------------------
echo "Building project..."
if ! sudo -u pi ./node_modules/.bin/babel src -d dist --copy-files --keep-file-extension; then
    echo "Build failed"
    exit 1
fi

# Restore original swap size
echo "Restoring swap configuration..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=100/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart

# ------------------------------------------------------
# Bluetooth Initialization Script
# ------------------------------------------------------
cat <<'EOF' | sudo tee /usr/local/bin/bluetooth-init.sh
#!/bin/bash
# File: /usr/local/bin/bluetooth-init.sh
# Location: /usr/local/bin
# Description: Initializes Bluetooth LE on hci0 with retry logic.
# Uses sudo only if not running as root.

# Determine if sudo is needed
if [ "$EUID" -ne 0 ]; then
    SUDO='sudo'
else
    SUDO=''
fi

MAX_RETRIES=5
RETRY_DELAY=2

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i: Initializing Bluetooth..."
    $SUDO hciconfig hci0 down
    sleep 2
    $SUDO btmgmt power on
    sleep 2
    $SUDO hciconfig hci0 up
    sleep 2
    $SUDO btmgmt le on
    sleep 2
    $SUDO hciconfig hci0 leadv
    if [ $? -eq 0 ]; then
        echo "Bluetooth initialized successfully."
        exit 0
    fi
    echo "Attempt $i failed, retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
done

echo "Failed to initialize Bluetooth after $MAX_RETRIES attempts."
exit 1
EOF

sudo chmod +x /usr/local/bin/bluetooth-init.sh

# ------------------------------------------------------
# Systemd Service: Bluetooth Initialization
# ------------------------------------------------------
cat <<'EOF' | sudo tee /etc/systemd/system/bluetooth-init.service
# File: /etc/systemd/system/bluetooth-init.service
[Unit]
Description=Bluetooth Initialization
After=bluetooth.service
Before=gymnasticon.service
Requires=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/bluetooth-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------
# Systemd Service: Gymnasticon
# ------------------------------------------------------
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
# File: /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth-init.service bluetooth.service network.target
Requires=bluetooth-init.service bluetooth.service

[Service]
Type=simple
# Note: Removed ExecStartPre so that Bluetooth is only initialized by bluetooth-init.service
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
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=no

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------
# Bluetooth Configuration: Set LE Mode
# ------------------------------------------------------
cat <<'EOF' | sudo tee /etc/bluetooth/main.conf
# File: /etc/bluetooth/main.conf
[General]
ControllerMode = le
EOF

# ------------------------------------------------------
# System Optimizations and Log Rotation
# ------------------------------------------------------
sudo usermod -a -G bluetooth pi
sudo setcap cap_net_raw,cap_net_admin+eip "$(readlink -f $(which node))"

cat <<EOF | sudo tee /etc/sysctl.d/99-bluetooth.conf
# File: /etc/sysctl.d/99-bluetooth.conf
kernel.sched_rt_runtime_us = 998000
EOF

cat <<EOF | sudo tee /etc/logrotate.d/gymnasticon
# File: /etc/logrotate.d/gymnasticon
/var/log/gymnasticon.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF

# ------------------------------------------------------
# Service Management
# ------------------------------------------------------
echo "Reloading systemd daemon and enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable bluetooth bluetooth-init gymnasticon
sudo systemctl start bluetooth
sleep 5
sudo systemctl start bluetooth-init
sleep 5
sudo systemctl start gymnasticon

# ------------------------------------------------------
# Final Verification
# ------------------------------------------------------
echo "Verifying Gymnasticon service..."
sleep 10
if systemctl is-active --quiet gymnasticon; then
    echo "Gymnasticon is running successfully."
else
    echo "Gymnasticon failed to start. Check logs with: journalctl -u gymnasticon"
    exit 1
fi

echo "Installation complete. Check service status with: sudo systemctl status gymnasticon"
