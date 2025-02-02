#!/bin/bash
# File: install.sh
# Folder: deploy
# Description: Installs Gymnasticon by cloning the repository into /opt/gymnasticon,
#              installing dependencies using npm ci if a lockfile is present, caching
#              dependencies if already installed, building the code with Babel, setting up
#              a local node/bin folder with a symlink to the Gymnasticon binary, and installing
#              the systemd service (running as user pi).

set -e

### Configuration Variables ###
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/var/log/gymnasticon-install.log"

### Start Logging ###
# Logging to LOG_FILE using sudo so we can write to /var/log
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

### 4. Verify Node.js is Installed ###
if ! command -v node >/dev/null; then
  # If 'node' is not found, check if 'nodejs' exists and create a symlink.
  if command -v nodejs >/dev/null; then
    echo "[NODE] 'node' not found, but 'nodejs' is available. Creating symlink..."
    sudo ln -sf "$(which nodejs)" /usr/bin/node
  else
    echo "ERROR: Node.js not found (v12.16.1 or later is required)."
    exit 1
  fi
fi
echo "[NODE] Found Node: $(node -v)"

### 5. Clone the Gymnasticon Repository into /opt/gymnasticon ###
echo "[GIT] Creating installation directory and cloning repository..."
sudo mkdir -p "$INSTALL_DIR"
# Set ownership to user pi so the service (running as pi) can write as needed.
sudo chown pi:pi "$INSTALL_DIR"
cd "$INSTALL_DIR"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

### 6. Set Up npm Environment Variables ###
echo "[NPM] Setting up npm environment..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
# You can adjust the number of jobs based on available memory; 2 is used here.
export npm_config_jobs=2
export NODE_OPTIONS="--max-old-space-size=256"
npm config set unsafe-perm true
npm config set legacy-peer-deps true

### 7. Install Dependencies Using Cache and npm ci ###
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

### 8. Build the Code Using Babel ###
echo "[BUILD] Building (transpiling) the source code..."
npm run build

### 9. Set Up Local Node/Bin for the Gymnasticon Binary ###
# The original service expects the binary at /opt/gymnasticon/node/bin/gymnasticon.
echo "[SETUP] Creating local node/bin directory and linking the binary..."
sudo mkdir -p "$INSTALL_DIR/node/bin"
# Link directly to the built file.
sudo ln -sf "$INSTALL_DIR/lib/app/cli.js" "$INSTALL_DIR/node/bin/gymnasticon"
sudo chmod +x "$INSTALL_DIR/lib/app/cli.js"
# Ensure proper ownership (user pi).
sudo chown -R pi:pi "$INSTALL_DIR"

### 10. Install the Original Systemd Service File ###
echo "[SERVICE] Installing systemd service file..."
sudo cp "${INSTALL_DIR}/deploy/gymnasticon.service" /etc/systemd/system/gymnasticon.service
echo "[SERVICE] Reloading systemd daemon and starting Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

### 11. Verify the Service Status ###
sleep 5
if systemctl is-active --quiet gymnasticon; then
    echo "[SERVICE] Gymnasticon service is active and running!"
else
    echo "ERROR: Gymnasticon service failed to start."
    sudo journalctl -u gymnasticon -n 50
    exit 1
fi

echo "=== Gymnasticon installation complete! ==="
