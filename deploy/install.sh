#!/bin/bash
# File: install.sh
# Folder: deploy
# Description: Installs Gymnasticon with proper Node.js setup and dependency management

set -e

### Configuration Variables ###
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/var/log/gymnasticon-install.log"

### Start Logging ###
exec > >(sudo tee -a "$LOG_FILE") 2>&1

### Error Handling ###
handle_error() {
    echo "ERROR: Something broke at line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

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
  jq

### 4. Install and Configure Node.js ###
echo "[NODE] Setting up Node.js..."
# Install Node.js from NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify Node.js installation
NODE_VERSION=$(node -v 2>/dev/null || true)
if [ -z "$NODE_VERSION" ]; then
    echo "[NODE] 'node' command not found. Checking for 'nodejs'..."
    NODE_VERSION=$(nodejs -v 2>/dev/null || true)
fi
if [ -z "$NODE_VERSION" ]; then
    echo "ERROR: Node.js installation failed."
    exit 1
fi
echo "[NODE] Node.js version: $NODE_VERSION"
echo "[NODE] npm version: $(npm -v)"

# Ensure the 'node' command is available system-wide.
if [ ! -x /usr/bin/node ]; then
    if [ -x /usr/bin/nodejs ]; then
        echo "[NODE] Creating symlink from /usr/bin/nodejs to /usr/bin/node..."
        sudo ln -sf /usr/bin/nodejs /usr/bin/node
    else
        # Fallback: use the path from which 'node' was found.
        NODE_CMD=$(which node || true)
        if [ -n "$NODE_CMD" ]; then
            echo "[NODE] Creating symlink from $NODE_CMD to /usr/bin/node..."
            sudo ln -sf "$NODE_CMD" /usr/bin/node
        else
            echo "ERROR: Could not determine Node.js binary location."
            exit 1
        fi
    fi
fi

# Optionally ensure 'npm' is in /usr/bin
if [ ! -x /usr/bin/npm ]; then
    NPM_CMD=$(which npm || true)
    if [ -n "$NPM_CMD" ]; then
        echo "[NODE] Creating symlink for npm..."
        sudo ln -sf "$NPM_CMD" /usr/bin/npm
    fi
fi

echo "[NODE] Node.js path: $(which node)"
echo "[NODE] npm path: $(which npm)"

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
export npm_config_jobs=2
export NODE_OPTIONS="--max-old-space-size=256"
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

### 10. Install Systemd Service ###
echo "[SERVICE] Installing systemd service file..."
sudo cp "${INSTALL_DIR}/deploy/gymnasticon.service" /etc/systemd/system/gymnasticon.service
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
