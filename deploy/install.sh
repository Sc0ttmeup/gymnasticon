#!/bin/bash
set -e

REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
SWAP_SIZE_MB=1024
LOG_FILE="/var/log/gymnasticon-install.log"

# Start logging (with sudo so we can write to /var/log)
exec > >(sudo tee -a "$LOG_FILE") 2>&1

cleanup_swap() {
    if [ -f /swapfile ]; then
        echo "[SWAP] Removing old /swapfile..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi
}

setup_swap() {
    echo "[SWAP] Creating a ${SWAP_SIZE_MB}MB swap file with dd..."
    cleanup_swap
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
}

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

handle_error() {
    echo "ERROR: Something broke at line $1"
    cleanup_swap
    exit 1
}

trap 'handle_error $LINENO' ERR

echo "=== Gymnasticon Install Script Starting ==="

# 1. Stop and remove any previous Gymnasticon
echo "[SERVICE] Stopping and removing old Gymnasticon installation..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# 2. Clean apt locks
cleanup_locks

# 3. Update and install system dependencies
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

# 4. Ensure Node.js is installed
if ! command -v node >/dev/null; then
  echo "ERROR: Node.js not found (v14.x is recommended)."
  exit 1
fi
echo "[NODE] Found Node: $(node -v)"

# 5. Create /opt/gymnasticon
sudo mkdir -p "$INSTALL_DIR"
sudo chown "$USER":"$USER" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 6. Clone the repository
echo "[GIT] Cloning Gymnasticon..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

# 7. Create swap & install everything
setup_swap

echo "[NPM] Setting up environment..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=256"

npm config set unsafe-perm true
npm config set legacy-peer-deps true

echo "[NPM] Installing Babel locally..."
npm install \
  @babel/cli \
  @babel/core \
  @babel/plugin-transform-modules-commonjs \
  @babel/preset-env \
  --no-save --build-from-source --unsafe-perm

echo "[NPM] Installing production deps..."
npm install --production --unsafe-perm --build-from-source

# 8. Configure Babel
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

# Force "type": "commonjs" so Node 14 can run compiled output easily
jq '. + {"type":"commonjs"}' package.json > package.json.tmp && mv package.json.tmp package.json

echo "[BABEL] Transpiling..."
npx babel src --out-dir lib

cleanup_swap

# 9. Verify output
if [ ! -f lib/app/cli.js ]; then
    echo "ERROR: lib/app/cli.js not found! Build failed."
    ls -la lib/app
    exit 1
fi
echo "[BABEL] Build success, found lib/app/cli.js"

# Create config file if you like, or skip
cat <<EOF > "$INSTALL_DIR/gymnasticon.json"
{
  "server-name": "Gymnasticon"
}
EOF

# 10. Install systemd service
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth.target
Requires=bluetooth.target
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=PATH=/usr/local/bin:/opt/gymnasticon/node_modules/.bin
WorkingDirectory=$INSTALL_DIR
User=$USER
Group=$USER
# Added flags: --ant --ant-bsc --ble-csc --ble-device-name
ExecStart=/usr/local/bin/node $INSTALL_DIR/lib/app/cli.js \\
  --config gymnasticon.json \\
  --ant \\
  --ant-bsc \\
  --ble-csc \\
  --ble-device-name "Gymnasticon"

RestartSec=1
Restart=always
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# 11. Check service
sleep 3
if systemctl is-active --quiet gymnasticon; then
    echo "[SERVICE] Gymnasticon is active and running!"
else
    echo "ERROR: Gymnasticon service failed to start."
    journalctl -u gymnasticon -n 50
    exit 1
fi

echo "=== Gymnasticon installation complete! ==="
