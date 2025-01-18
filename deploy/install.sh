#!/bin/bash
set -e

# Configuration
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/home/pi/install.log"

# Start logging
exec > >(tee -a $LOG_FILE) 2>&1

echo "Starting installation of Gymnasticon..."

# Clean up previous installation
echo "Removing previous installations..."
sudo systemctl stop gymnasticon || true
sudo systemctl disable gymnasticon || true
sudo rm -rf $INSTALL_DIR
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl

# Clone the Gymnasticon repository
echo "Cloning the Gymnasticon repository..."
git clone --depth 1 --branch $BRANCH $REPO_URL $INSTALL_DIR

# Set permissions
echo "Setting permissions for $INSTALL_DIR..."
sudo chown -R pi:pi $INSTALL_DIR

# Install npm packages
echo "Installing npm packages..."
cd $INSTALL_DIR
npm install
npm rebuild

# Configure the systemd service
echo "Setting up systemd service..."
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
EOL

# Start the service
echo "Enabling and starting the Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete! Gymnasticon is now running as a service."
