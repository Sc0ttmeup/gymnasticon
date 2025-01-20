#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/home/pi/install.log"
NODE_VERSION="14.x"
NODE_SETUP_URL="https://deb.nodesource.com/setup_${NODE_VERSION}"

# Start logging
exec > >(tee -a $LOG_FILE) 2>&1

# Helper functions
show_progress() {
    echo "[$1] $2"
    sleep 1
}

handle_error() {
    echo "Error occurred at line $1"
    exit 1
}

check_node_version() {
    if command -v node >/dev/null; then
        echo "Using pre-installed Node.js $(node -v)"
        return 0
    else
        echo "Node.js not found. Please ensure your OS image includes Node.js"
        exit 1
    fi
}

validate_permissions() {
    if ! groups | grep -q bluetooth; then
        sudo usermod -a -G bluetooth $USER
    fi
}

trap 'handle_error $LINENO' ERR

show_progress "1/7" "Starting installation of Gymnasticon..."

# Clean removal of previous installation
show_progress "2/7" "Removing previous installations..."
sudo systemctl stop gymnasticon || true
sudo systemctl disable gymnasticon || true
sudo rm -rf $INSTALL_DIR
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# System dependencies
show_progress "3/7" "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    git=1:2.20.1* \
    bluetooth=5.50* \
    bluez=5.50* \
    libbluetooth-dev=5.50* \
    libudev-dev=241* \
    libusb-1.0-0-dev=2:1.0.22* \
    build-essential=12.6* \
    curl=7.64.0* \
    jq

# Node.js setup
show_progress "4/7" "Installing Node.js..."
check_node_version

# Create installation directory with proper permissions
show_progress "5/7" "Setting up Gymnasticon..."
sudo mkdir -p $INSTALL_DIR
sudo chown $USER:$USER $INSTALL_DIR
cd $INSTALL_DIR || exit 1

# Repository setup
git clone --depth 1 --branch $BRANCH $REPO_URL .

# Dependencies and build
show_progress "6/7" "Installing dependencies..."

# Install global dependencies first
npm install -g @babel/cli @babel/core

# Install project dependencies
npm install --no-audit --no-fund

# Verify source directory exists
if [ ! -d "src" ]; then
    git clone --depth 1 --branch $BRANCH $REPO_URL src_temp
    mv src_temp/src .
    rm -rf src_temp
fi

# Create necessary directories
mkdir -p lib/app

# Install babel dependencies locally to ensure they're available
npm install --save-dev @babel/cli @babel/core @babel/preset-env

# Configure babel
echo '{
  "presets": ["@babel/preset-env"]
}' > .babelrc

# Run babel build with specific source file
NODE_ENV=production npx babel src --out-dir lib --verbose

# Verify the output
if [ -f "lib/app/cli.js" ]; then
    echo "Build successful - cli.js generated"
    # Test the file
    node -c lib/app/cli.js
else
    echo "Build failed - cli.js not found"
    ls -la lib/app/
    ls -la src/app/
    exit 1
fi

# Set permissions
sudo chown -R $USER:$USER $INSTALL_DIR
validate_permissions

# Service setup
show_progress "7/7" "Configuring service..."
sudo tee /etc/systemd/system/gymnasticon.service > /dev/null <<EOL
[Unit]
Description=Gymnasticon
After=bluetooth.target
Requires=bluetooth.target
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=PATH=/usr/local/bin:/opt/gymnasticon/node_modules/.bin
WorkingDirectory=$INSTALL_DIR
User=pi
Group=pi
ExecStart=/usr/local/bin/node $INSTALL_DIR/lib/app/cli.js
RestartSec=1
Restart=always
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOL

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Verify service
timeout 30 systemctl status gymnasticon || {
    echo "Service failed to start properly"
    journalctl -u gymnasticon -n 50
    exit 1
}

show_progress "Complete" "Gymnasticon is now running as a service!"
