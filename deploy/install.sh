#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"

echo "Installing Gymnasticon..."

# Ensure required dependencies are installed
echo "Installing dependencies (excluding nodejs and npm)..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential

# Clone the repository
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
echo "Setting permissions..."
sudo chown -R $USER:$USER $INSTALL_DIR

# Install npm packages using the installed Node.js
echo "Installing npm packages..."
cd $INSTALL_DIR
/home/pi/.nvm/versions/node/v14.*/bin/npm install

# Setup systemd service
echo "Setting up systemd service..."
sudo tee /etc/systemd/system/gymnasticon.service > /dev/null << EOL
[Unit]
Description=Gymnasticon Service
After=bluetooth.target
Wants=bluetooth.target

[Service]
ExecStart=/home/pi/.nvm/versions/node/v14.*/bin/node /opt/gymnasticon/src/gymnasticon.js
WorkingDirectory=/opt/gymnasticon
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the service
echo "Enabling and starting the Gymnasticon service..."
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete! Gymnasticon is now running as a service."
