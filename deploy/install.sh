#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
FORCE_INSTALL=${1:-false}

LOG_FILE="install.log"
echo "Starting installation..." | tee -a $LOG_FILE

# Redirect all output to the log file
exec > >(tee -a $LOG_FILE) 2>&1

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl

# Install Node.js for ARMv6
if [[ "$FORCE_INSTALL" == "true" ]] || ! command -v node > /dev/null || ! command -v npm > /dev/null; then
    echo "Node.js and npm are not installed or reinstallation is forced. Installing for ARMv6..."
    NODE_VERSION="14.21.3"
    NODE_DISTRO="linux-armv6l"
    NODE_ARCHIVE="node-v$NODE_VERSION-$NODE_DISTRO.tar.xz"
    NODE_URL="https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/$NODE_ARCHIVE"

    # Download Node.js
    echo "Downloading Node.js from $NODE_URL..."
    curl -o $NODE_ARCHIVE $NODE_URL

    # Validate the file format
    if ! file $NODE_ARCHIVE | grep -q "XZ compressed data"; then
        echo "Invalid Node.js archive format. Exiting."
        rm -f $NODE_ARCHIVE
        exit 1
    fi

    # Extract Node.js
    echo "Extracting Node.js..."
    sudo tar -xJf $NODE_ARCHIVE -C /usr/local --strip-components=1
    rm -f $NODE_ARCHIVE
    echo "Node.js installed successfully!"
else
    echo "Node.js and npm are already installed."
fi

# Clone the Gymnasticon repository
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Cloning repository..."
    sudo git clone --depth 1 --branch $BRANCH $REPO_URL $INSTALL_DIR
else
    echo "Repository already exists at $INSTALL_DIR. Pulling latest changes..."
    cd $INSTALL_DIR
    sudo git reset --hard
    sudo git pull origin $BRANCH
fi

# Set permissions
echo "Setting permissions for $INSTALL_DIR..."
sudo chown -R $USER:$USER $INSTALL_DIR

# Install npm packages
echo "Installing npm packages..."
cd $INSTALL_DIR
npm install
npm rebuild
# Set up systemd service

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

ExecStart=/usr/local/bin/node $INSTALL_DIR/src/cli.js
RestartSec=1
Restart=always

AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target

EOL# Enable and start the service
echo "Enabling and starting the Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete! Gymnasticon is now running as a service."
