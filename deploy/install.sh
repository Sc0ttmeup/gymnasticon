#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/home/pi/install.log"
# Node.js version pinning
NODE_VERSION="14.x"
NODE_SETUP_URL="https://deb.nodesource.com/setup_${NODE_VERSION}"

# Start logging
exec > >(tee -a $LOG_FILE) 2>&1

# Progress and error handling functions
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

# Remove previous installations
show_progress "2/7" "Removing previous installations..."
sudo systemctl stop gymnasticon || true
sudo systemctl disable gymnasticon || true
sudo rm -rf $INSTALL_DIR
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Install system dependencies
show_progress "3/7" "Installing system dependencies..."
sudo apt-get update
# Install system dependencies with version pins
sudo apt-get install -y \
    git=1:2.20.1* \
    bluetooth=5.50* \
    bluez=5.50* \
    libbluetooth-dev=5.50* \
    libudev-dev=241* \
    libusb-1.0-0-dev=2:1.0.22* \
    build-essential=12.6* \
    curl=7.64.0*

# Install Node.js
show_progress "4/7" "Installing Node.js..."


check_node_version

# Clone repository
show_progress "5/7" "Setting up Gymnasticon..."
if [ ! -d "$INSTALL_DIR" ]; then
    sudo mkdir -p $INSTALL_DIR
    sudo chown $USER:$USER $INSTALL_DIR
    git clone --depth 1 --branch $BRANCH $REPO_URL $INSTALL_DIR
else
    cd $INSTALL_DIR
    sudo git reset --hard
    sudo git pull origin $BRANCH
fi

# Set permissions and validate
sudo chown -R $USER:$USER $INSTALL_DIR
validate_permissions
# Install npm packages with detailed progress
show_progress "6/7" "Installing dependencies..."
cd $INSTALL_DIR
echo "Installing npm packages..."
npm install --no-audit --no-fund --loglevel=info | grep -E "added|removed|changed|finished"
echo "Building application..."
npm run build --loglevel=info | grep -E "webpack|asset|entrypoint|chunks|modules"
# Set up systemd service
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

# Enable and verify service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

# Verify service status
timeout 30 systemctl status gymnasticon || {
    echo "Service failed to start properly"
    exit 1
}

show_progress "Complete" "Gymnasticon is now running as a service!"

check_os_version() {
    if ! grep -q "buster" /etc/os-release; then
        echo "This script requires Raspbian Buster Lite (2021)"
        exit 1
    }
}

check_architecture() {
    if ! uname -m | grep -q "armv6l"; then
        echo "This script requires ARMv6 architecture (Raspberry Pi Zero)"
        exit 1
    }
}
