#!/bin/bash
# File: install.sh
# Folder: deploy
# Description: Installs Gymnasticon with Node.js v14 on ARMv6 (RPi Zero).

set -e

### Configuration Variables ###
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/var/log/gymnasticon-install.log"
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
TEMP_DIR="/tmp/gymnasticon-install"

### Start Logging ###
exec > >(sudo tee -a "$LOG_FILE") 2>&1

### Error and Cleanup Handling ###
handle_error() {
    echo "ERROR: Something broke at line $1"
    cleanup_temp
    exit 1
}

cleanup_temp() {
    echo "[CLEANUP] Removing temporary files..."
    rm -rf "${TEMP_DIR}"
}

trap 'handle_error $LINENO' ERR
trap cleanup_temp EXIT

### Clean Up APT Locks ###
cleanup_locks() {
    echo "[APT] Cleaning up package manager locks..."
    while sudo lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "APT is busy, waiting..."
        sleep 5
    done
    sudo killall apt apt-get 2>/dev/null || true
    sudo rm -f /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/dpkg/lock*
    sudo dpkg --configure -a
    sleep 2
}

echo "=== Gymnasticon Install Script Starting ==="

### 1. Stop and Remove Any Previous Installation ###
echo "[SERVICE] Stopping and removing any previous Gymnasticon installation..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

### 2. Clean APT Locks and Update Packages ###
cleanup_locks
echo "[APT] Updating package lists..."
sudo apt-get update

### 3. Install Required System Dependencies ###
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
  jq \
  xz-utils

### 4. Install and Configure Node.js (Version 14 for ARMv6) ###
echo "[NODE] Installing Node.js v${NODE_VERSION} for ARMv6..."

# Create and enter temp directory
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# Verify and download Node.js binary
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
if ! curl --output /dev/null --silent --head --fail "$NODE_DOWNLOAD_URL"; then
    echo "ERROR: Node.js binary not available at $NODE_DOWNLOAD_URL"
    exit 1
fi

curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/

# Set up PATH and verify installation
export PATH="/usr/local/bin:$PATH"
hash -r

NODE_VERSION_INSTALLED=$(node -v 2>/dev/null || true)
if [ -z "$NODE_VERSION_INSTALLED" ]; then
    echo "ERROR: Node.js installation failed."
    exit 1
fi

echo "[NODE] Node.js version: $NODE_VERSION_INSTALLED"
echo "[NODE] npm version: $(npm -v)"

# Create system-wide symlinks
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

### 5. Clone the Gymnasticon Repository ###
echo "[GIT] Creating installation directory and cloning repository..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown pi:pi "$INSTALL_DIR"
cd "$INSTALL_DIR"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

### 6. Set Up npm Environment Variables ###
echo "[NPM] Setting up npm environment..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=128"
npm config set unsafe-perm true
npm config set legacy-peer-deps true

### 7. Install Dependencies ###
if [ ! -d "node_modules" ]; then
    if [ -f package-lock.json ]; then
        echo "[NPM] Installing dependencies using npm ci..."
        npm ci
    else
        echo "[NPM] Installing dependencies using npm install..."
        npm install
    fi
else
    echo "[NPM] Dependencies already installed. Skipping installation."
fi

### 8. Build the Code ###
echo "[BUILD] Building (transpiling) the source code..."
npm run build

### 9. Set Up Local Binary ###
echo "[SETUP] Creating local node/bin directory and linking the binary..."
sudo mkdir -p "$INSTALL_DIR/node/bin"
sudo ln -sf "$INSTALL_DIR/lib/app/cli.js" "$INSTALL_DIR/node/bin/gymnasticon"
sudo chmod +x "$INSTALL_DIR/lib/app/cli.js"
sudo chown -R pi:pi "$INSTALL_DIR"

### 10. Install Systemd Service and Configure ###
echo "[SERVICE] Installing systemd service file..."
sudo cp "${INSTALL_DIR}/deploy/gymnasticon.service" /etc/systemd/system/gymnasticon.service

# Configure service with proper PATH and resource limits
sudo sed -i '/\[Service\]/a Environment=PATH=/usr/local/bin:/usr/bin:/bin\nMemoryLimit=150M\nCPUQuota=80%' /etc/systemd/system/gymnasticon.service

echo "[SERVICE] Reloading systemd daemon and starting Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

### 11. Verify Service Status ###
sleep 5
if systemctl is-active --quiet gymnasticon; then
    echo "[SERVICE] Gymnasticon service is active and running!"
else
    echo "ERROR: Gymnasticon service failed to start."
    sudo journalctl -u gymnasticon -n 50
    exit 1
fi

echo "=== Gymnasticon installation complete! ==="

