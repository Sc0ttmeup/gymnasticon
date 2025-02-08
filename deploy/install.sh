#!/bin/bash
set -e

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"

# Environment setup
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*

# System preparation
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Verify Node.js installation
node -v
npm -v

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo rm -rf "$INSTALL_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$INSTALL_DIR"
cd "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"

# NPM setup
sudo -u pi npm config set unsafe-perm true
sudo -u pi npm config set legacy-peer-deps true
sudo -u pi npm config set audit false

# Install dependencies
echo "Installing dependencies..."
sudo -u pi npm install --save-dev @babel/core @babel/cli @babel/preset-env
sudo -u pi npm install --production

# Configure Babel
cat > .babelrc << 'EOF'
{
  "presets": [
    ["@babel/preset-env", {
      "targets": {
        "node": "14"
      },
      "modules": "commonjs"
    }]
  ]
}
EOF

# Build step
sudo -u pi ./node_modules/.bin/babel src -d dist --copy-files

# Configure Bluetooth
sudo usermod -a -G bluetooth pi
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)
sudo btmgmt le on

echo "[General]
ControllerMode = le
" | sudo tee -a /etc/bluetooth/main.conf

sudo systemctl enable bluetooth
sudo systemctl start bluetooth
sleep 5

# Create systemd service file
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth.service network.target
Wants=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/node $INSTALL_DIR/dist/app/cli.js
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=10
User=pi
Group=pi
Environment=NODE_ENV=production
Environment=DEBUG=gym:*
Environment=NOBLE_HCI_DEVICE_ID=hci0
Environment=BLENO_HCI_DEVICE_ID=hci0
Environment=NOBLE_MULTI_ROLE=1
SyslogIdentifier=gymnasticon

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions
sudo chown root:root /etc/systemd/system/gymnasticon.service
sudo chmod 644 /etc/systemd/system/gymnasticon.service

# Start service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "Installation complete. Check status with: sudo systemctl status gymnasticon"
