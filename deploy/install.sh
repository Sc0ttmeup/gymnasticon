#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"

echo "Installing Gymnasticon..."

# Install required dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y git nodejs npm bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential


# Clone the repository
echo "Cloning repository..."
sudo git clone --depth 1 --branch $BRANCH $REPO_URL $INSTALL_DIR

# Set permissions
sudo chown -R $USER:$USER $INSTALL_DIR

# Install npm packages
echo "Installing npm packages..."
cd $INSTALL_DIR
npm install

# Setup systemd service
echo "Setting up systemd service..."
sudo tee /etc/systemd/system/gymnasticon.service > /dev/null << EOL
[Unit]
Description=Gymnasticon Service
After=bluetooth.target
Wants=bluetooth.target

[Service]
ExecStart=/usr/bin/node /opt/gymnasticon/src/gymnasticon.js
WorkingDirectory=/opt/gymnasticon
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOL

# Enable and start service
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete! Gymnasticon is now running as a service."
