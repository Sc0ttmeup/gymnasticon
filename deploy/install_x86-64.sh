#!/bin/bash
set -euo pipefail

if [[ $(/usr/bin/id -u) -eq 0 ]]; then
    echo "WARNING: Running as root"
    echo "If you have a regular user account you would prefer to be able to run gymnasticon please install using that account instead."
    read -rsp $'Press Ctrl+C to quit or any other key to continue\n' -n1 key
    echo 'Continuing'
fi

# Record start time
START_TIME=$(date +%s)

# Configuration
#NODE_VERSION="12.22.12" #Original gymnasticon installer version
NODE_VERSION="14.21.3" # 4o4R script version
NODE_DISTRO="node-v${NODE_VERSION}-linux-x64"
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"

# Environment setup
#export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*
export MAKEFLAGS=-j1

# System checks
if ! /usr/bin/uname -m | grep -q "x86_64"; then
    echo "This script must be run on x86-64"
    exit 1
fi

# Bluetooth checks and setup
if ! command -v hciconfig >/dev/null 2>&1; then
    echo "Installing bluetooth tools..."
    sudo apt-get update
    sudo apt-get install -y bluetooth bluez bluez-tools
fi

# Reset Bluetooth adapter
sudo hciconfig hci0 down
sudo /usr/sbin/modprobe -r btusb
sudo /usr/sbin/modprobe btusb
sudo hciconfig hci0 up
sudo systemctl restart bluetooth

# System preparation
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils #dphys-swapfile

# Clean existing installation
echo "Cleaning up any existing installation..."
sudo systemctl stop gymnasticon || true
sudo systemctl disable gymnasticon || true
sudo rm -f /var/log/gymnasticon.log
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
if test -f "${NODE_DISTRO}.tar.xz"; then
  sudo rm -f "${NODE_DISTRO}.tar.xz"
fi
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
sudo tar -C /usr/local/ --strip-components=1 -xf "${NODE_DISTRO}.tar.xz"
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Install Gymnasticon
echo "Installing Gymnasticon..."
#sudo git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
sudo git clone --depth 1 https://github.com/Sc0ttmeup/gymnasticon.git "$INSTALL_DIR" -b x86-64-Buster --single-branch
INSTALL_DIR_OWNER=$(stat -c '%U' "$INSTALL_DIR")
INSTALL_DIR_GROUP=$(stat -c '%G' "$INSTALL_DIR")
sudo chown -R root:root "$INSTALL_DIR"
cd "$INSTALL_DIR"

# NPM setup and installation
echo "Setting up NPM configuration..."
sudo npm config set unsafe-perm true
sudo npm config set legacy-peer-deps true
sudo npm config set audit false
sudo npm config set fund false
sudo npm config set update-notifier false

echo "Installing dependencies..."
sudo npm install --no-optional --unsafe-perm --build-from-source
sudo npm install @abandonware/bluetooth-hci-socket --unsafe-perm --build-from-source

echo "Building project..."
sudo npm run build

# Verify build
if [ ! -f "$INSTALL_DIR/lib/app/cli.js" ]; then
    echo "Build failed - cli.js not found"
    exit 1
fi

# Reset ownership
sudo chown -R "$INSTALL_DIR_OWNER:$INSTALL_DIR_GROUP" "$INSTALL_DIR"

# Service setup
echo "Installing service files..."
sudo cp "${INSTALL_DIR}/deploy/gymnasticon.service" /etc/systemd/system/

# Configure Bluetooth
cat <<'EOF' | sudo tee /etc/bluetooth/main.conf
[General]
#ControllerMode = le
ControllerMode = dual
Privacy = off
EOF

# Reset Bluetooth adapter
sudo hciconfig hci0 down
sudo /usr/sbin/modprobe -r btusb
sudo /usr/sbin/modprobe btusb
sudo hciconfig hci0 up
sleep 2

sudo btmgmt le on
sudo bluetoothctl system-alias 'Gymnasticon2'
sudo hciconfig hci0 name 'Gymnasticon2'
sudo systemctl restart bluetooth
sleep 2

# USB permissions
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1009", MODE="0666"' | sudo tee /etc/udev/rules.d/99-garmin.rules
sudo usermod -a -G plugdev,bluetooth "$USER"
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

# Verify installation
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

# Record end time and show completion message
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Installation completed in ${DURATION} seconds."
echo "Verify installation with:"
echo "- sudo systemctl status gymnasticon"
echo "- journalctl -u gymnasticon -f"
echo "- sudo hcitool lescan"
