#!/bin/bash
# File: install.sh
# Folder: /opt/gymnasticon
# Description: Full installation script for Gymnasticon on a Raspberry Pi Zero.
#              This script clones, builds (transpiles) and configures Gymnasticon,
#              creates a configuration file enabling both ANT+ and Bluetooth broadcasting,
#              and sets up a systemd service running as root.
#              It uses 'npm link' (instead of 'npm install -g .') to globally install the package.

set -e

# --- Configuration Variables ---
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
SWAP_SIZE_MB=1024
LOG_FILE="/var/log/gymnasticon-install.log"

# --- Start Logging ---
# Logging to LOG_FILE (using sudo so we can write to /var/log)
exec > >(sudo tee -a "$LOG_FILE") 2>&1

# --- Error Handling ---
handle_error() {
    echo "ERROR: Something broke at line $1"
    cleanup_swap
    exit 1
}
trap 'handle_error $LINENO' ERR

# --- Swap File Functions ---
cleanup_swap() {
    if [ -f /swapfile ]; then
        echo "[SWAP] Removing old /swapfile..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi
}

setup_swap() {
    echo "[SWAP] Creating a ${SWAP_SIZE_MB}MB swap file..."
    cleanup_swap
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
}

# --- APT Lock Cleanup ---
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

# --- 1. Stop and Remove Previous Installation ---
echo "[SERVICE] Stopping and removing old Gymnasticon installation..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# --- 2. Clean APT Locks ---
cleanup_locks

# --- 3. Update APT and Install Dependencies ---
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

# --- 4. Ensure Node.js Is Installed (v14.x recommended) ---
if ! command -v node >/dev/null; then
  echo "ERROR: Node.js not found (v14.x is recommended)."
  exit 1
fi
echo "[NODE] Found Node: $(node -v)"

# --- 5. Create Installation Directory ---
sudo mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- 6. Clone the Repository ---
echo "[GIT] Cloning Gymnasticon from $REPO_URL..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

# --- 7. Set Up Swap Space ---
setup_swap

# --- 8. Set Up Environment Variables for npm Build ---
echo "[NPM] Setting up environment variables..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=256"

npm config set unsafe-perm true
npm config set legacy-peer-deps true

# --- 9. Install Babel Packages ---
echo "[NPM] Installing Babel packages..."
npm install \
  @babel/cli \
  @babel/core \
  @babel/plugin-transform-modules-commonjs \
  @babel/preset-env \
  --no-save --build-from-source --unsafe-perm

# --- 10. Install Production Dependencies ---
echo "[NPM] Installing production dependencies..."
npm install --production --unsafe-perm --build-from-source

# --- 11. Configure Babel (.babelrc) ---
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

# --- 12. Transpile the Source Code ---
echo "[BABEL] Transpiling source files..."
npx babel src --out-dir lib

# --- 13. Globally Install via npm link Instead of npm install -g ---
echo "[NPM] Cleaning npm cache..."
npm cache clean --force

echo "[NPM] Linking Gymnasticon globally..."
npm link

cleanup_swap

# --- 14. Verify Build Output ---
if [ ! -f lib/app/cli.js ]; then
    echo "ERROR: lib/app/cli.js not found! Build failed."
    ls -la lib/app
    exit 1
fi
echo "[BABEL] Build success; lib/app/cli.js exists."

# --- 15. Create the Configuration File ---
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

# --- 16. Create and Install systemd Service ---
# Running as root (User/Group lines are omitted)
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
ExecStart=/usr/local/bin/gymnasticon
RestartSec=1
Restart=always
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# --- 17. Reload systemd and Start the Service ---
echo "[SERVICE] Reloading systemd daemon and starting Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Optional: Wait a few seconds to allow hardware initialization
sleep 5

# --- 18. Check Service Status ---
if systemctl is-active --quiet gymnasticon; then
    echo "[SERVICE] Gymnasticon service is active and running!"
else
    echo "ERROR: Gymnasticon service failed to start."
    journalctl -u gymnasticon -n 50
    exit 1
fi

echo "=== Gymnasticon installation complete! ==="
