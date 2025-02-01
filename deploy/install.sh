#!/bin/bash
# File: install.sh
# Folder: /opt/gymnasticon
# Description: Full installation script for Gymnasticon on a Raspberry Pi Zero.
#              This script builds, installs, and configures Gymnasticon and sets up
#              a systemd service that runs as root (so Bluetooth adapter access is allowed).

set -e

# Configuration variables
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
SWAP_SIZE_MB=1024
LOG_FILE="/var/log/gymnasticon-install.log"

# Start logging (using sudo so we can write to /var/log)
exec > >(sudo tee -a "$LOG_FILE") 2>&1

# Error handling function
handle_error() {
    echo "ERROR: Something broke at line $1"
    cleanup_swap
    exit 1
}
trap 'handle_error $LINENO' ERR

# Remove any existing swap file
cleanup_swap() {
    if [ -f /swapfile ]; then
        echo "[SWAP] Removing old /swapfile..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi
}

# Create a new swap file
setup_swap() {
    echo "[SWAP] Creating a ${SWAP_SIZE_MB}MB swap file..."
    cleanup_swap
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
}

# Clean up APT locks if present
cleanup_locks() {
    echo "[APT] Cleaning up package manager locks..."
    while sudo lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "APT is busy, waiting..."
        sleep 5
    done

    sudo killall apt apt-get 2>/dev/null || true
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo dpkg --configure -a
    sleep 2
}

echo "=== Gymnasticon Install Script Starting ==="

# 1. Stop and remove any previous installation
echo "[SERVICE] Stopping and removing old Gymnasticon installation..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# 2. Clean APT locks
cleanup_locks

# 3. Update APT package lists and install dependencies
echo "[APT] Updating package lists..."
sudo apt-get update

echo "[APT] Installing dependencies..."
sudo apt-get install -y \
  git \
  bluetooth \
  bluez \
  libbluetooth-dev \
  libudev-dev \
  libusb-1.0-0-dev \
  build-essential \
  curl \
  jq

# 4. Ensure Node.js is installed (v14.x recommended)
if ! command -v node >/dev/null; then
  echo "ERROR: Node.js not found (v14.x is recommended)."
  exit 1
fi
echo "[NODE] Found Node: $(node -v)"

# 5. Create the installation directory and set ownership
sudo mkdir -p "$INSTALL_DIR"
# Since we plan to run as root, ownership can remain root.
cd "$INSTALL_DIR"

# 6. Clone the repository
echo "[GIT] Cloning Gymnasticon from $REPO_URL..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

# 7. Set up swap space for resource-constrained build (RPi Zero)
setup_swap

# 8. Set up environment variables for npm and build options
echo "[NPM] Setting up environment variables..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=256"

npm config set unsafe-perm true
npm config set legacy-peer-deps true

# 9. Install Babel locally for transpiling
echo "[NPM] Installing Babel packages..."
npm install \
  @babel/cli \
  @babel/core \
  @babel/plugin-transform-modules-commonjs \
  @babel/preset-env \
  --no-save --build-from-source --unsafe-perm

# 10. Install production dependencies
echo "[NPM] Installing production dependencies..."
npm install --production --unsafe-perm --build-from-source

# 11. Transpile the code using Babel
echo "[BABEL] Creating .babelrc..."
cat <<EOF > .babelrc
{
  "presets": [
    ["@babel/preset-env", {
      "targets": { "node": "14" },
      "modules": "commonjs"
    }]
  ],
  "plugins": [
    "@babel/plugin-transform-modules-commonjs"
  ]
}
EOF

echo "[BABEL] Updating package.json to use commonjs modules..."
jq '. + {"type":"commonjs"}' package.json > package.json.tmp && mv package.json.tmp package.json

echo "[BABEL] Transpiling source files..."
npx babel src --out-dir lib

# 12. Install the package globally so the binary is available
echo "[NPM] Installing Gymnasticon globally..."
npm install -g .

cleanup_swap

# 13. Verify that the build produced the expected file
if [ ! -f lib/app/cli.js ]; then
    echo "ERROR: lib/app/cli.js not found! Build failed."
    ls -la lib/app
    exit 1
fi
echo "[BABEL] Build success; lib/app/cli.js exists."

# 14. Create (or update) the configuration file to enable broadcasting for both ANT+ and Bluetooth.
echo "[CONFIG] Creating configuration file..."
cat <<EOF > "$INSTALL_DIR/gymnasticon.json"
{
  "server-name": "Gymnasticon",
  "broadcast": {
    "ant": {
      "power": true,
      "speedCadence": true
    },
    "bluetooth": {
      "power": true,
      "speedCadence": true
    }
  }
}
EOF

# 15. Install and configure the systemd service.
#     Running as root so remove User/Group lines.
echo "[SERVICE] Creating systemd service file..."
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth.target
Requires=bluetooth.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
# Running as root; no User/Group directives.
ExecStart=/usr/local/bin/gymnasticon
RestartSec=1
Restart=always
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon, enable and start the service
echo "[SERVICE] Reloading systemd daemon and starting Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Optional: Wait a few seconds to allow hardware initialization
sleep 5

# 16. Check service status
if systemctl is-active --quiet gymnasticon; then
    echo "[SERVICE] Gymnasticon service is active and running!"
else
    echo "ERROR: Gymnasticon service failed to start."
    journalctl -u gymnasticon -n 50
    exit 1
fi

echo "=== Gymnasticon installation complete! ==="
