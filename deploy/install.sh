#!/bin/bash
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
export MAKEFLAGS=-j1

# System checks
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo "This script must be run on a Raspberry Pi"
    exit 1
fi

if ! hciconfig | grep -q "hci0"; then
    echo "No Bluetooth adapter (hci0) found"
    exit 1
fi

# System preparation
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils dphys-swapfile

# Increase swap
echo "Configuring swap space..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
sudo tar -C /usr/local/ --strip-components=1 -xf "${NODE_DISTRO}.tar.xz"
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo rm -rf "$INSTALL_DIR"
sudo git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"

# NPM Configuration
cd "$INSTALL_DIR"
sudo -u pi npm config set unsafe-perm true
sudo -u pi npm config set legacy-peer-deps true
sudo -u pi npm config set audit false
sudo -u pi npm config set fund false
sudo -u pi npm config set update-notifier false

# Install dependencies
echo "Installing dependencies..."
sudo -u pi npm install --save-dev @babel/core @babel/cli @babel/preset-env
sudo -u pi npm install --production --no-optional --legacy-peer-deps

# Build project
echo "Building project..."
sudo -u pi ./node_modules/.bin/babel src -d dist --copy-files --keep-file-extension

# Restore swap
echo "Restoring swap configuration..."
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=100/' /etc/dphys-swapfile
sudo /etc/init.d/dphys-swapfile restart

# Create bluetooth init script
cat <<'EOF' | sudo tee /usr/local/bin/bluetooth-init.sh
#!/bin/bash
SUDO=''
[ "$EUID" -ne 0 ] && SUDO='sudo'

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

# Create systemd services
cat <<'EOF' | sudo tee /etc/systemd/system/bluetooth-init.service
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

cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth-init.service bluetooth.service network.target
Requires=bluetooth-init.service bluetooth.service

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
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=no

[Install]
WantedBy=multi-user.target
EOF

# Configure Bluetooth
cat <<'EOF' | sudo tee /etc/bluetooth/main.conf
[General]
ControllerMode = le
EOF

# System optimizations
sudo usermod -a -G bluetooth pi
sudo setcap cap_net_raw,cap_net_admin+eip "$(readlink -f $(which node))"

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

# Enable and start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable bluetooth bluetooth-init gymnasticon
sudo systemctl start bluetooth
sleep 5
sudo systemctl start bluetooth-init
sleep 5
sudo systemctl start gymnasticon

# Verify installation
echo "Verifying Gymnasticon service..."
sleep 10
if systemctl is-active --quiet gymnasticon; then
    echo "Gymnasticon is running successfully."
else
    echo "Gymnasticon failed to start. Check logs with: journalctl -u gymnasticon"
    exit 1
fi

echo "Installation complete. Check service status with: sudo systemctl status gymnasticon"
