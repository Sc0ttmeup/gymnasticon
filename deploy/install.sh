#!/bin/bash
# Installation script for Gymnasticon on RPiZero with Node 14

set -e

echo "=== Starting Gymnasticon Installation ==="

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"
TMP_CLONE_DIR="/tmp/gymnasticon-clone"

# Environment setup for low-memory devices
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true
export DEBUG=gym:*

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"

# Check and install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils coreutils

# Configure Bluetooth for both receiving and broadcasting
echo "Configuring Bluetooth..."
sudo btmgmt le on
echo "[General]
ControllerMode = le
" | sudo tee -a /etc/bluetooth/main.conf

# Clean up existing Node installation
echo "Cleaning up existing Node installation..."
sudo killall node || true
sudo rm -f /usr/local/bin/node
sudo rm -f /usr/bin/node
sudo rm -f /usr/local/bin/npm
sudo rm -f /usr/bin/npm

# Install Node.js
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Verify Node.js installation
echo "Verifying Node.js installation..."
node -v
npm -v

# Clone Gymnasticon repository
echo "Cloning Gymnasticon repository..."
rm -rf "$TMP_CLONE_DIR"
git clone --depth 1 https://github.com/4o4R/gymnasticon.git "$TMP_CLONE_DIR"

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R pi:pi "$INSTALL_DIR"
cp -R "$TMP_CLONE_DIR"/* "$INSTALL_DIR"
rm -rf "$TMP_CLONE_DIR"

# NPM setup and installation
echo "Setting up npm and installing dependencies..."
cd "$INSTALL_DIR"
npm config set unsafe-perm true
npm config set legacy-peer-deps true
npm config set audit false

# Install dependencies including Babel
echo "Installing dependencies and build tools..."
npm install --save-dev @babel/core @babel/cli @babel/preset-env
npm install --production

# Configure Babel
echo "Configuring Babel..."
echo '{
  "presets": [
    ["@babel/preset-env", {
      "targets": {
        "node": "14"
      },
      "modules": "commonjs"
    }]
  ]
}' > .babelrc

# Build step
echo "Building Gymnasticon..."
"$INSTALL_DIR/node_modules/.bin/babel" src -d dist --copy-files

# Create executable wrapper
echo "Creating executable wrapper..."
mkdir -p "$INSTALL_DIR/node/bin"
cat > "$INSTALL_DIR/node/bin/gymnasticon" << EOF
#!/bin/bash
NODE_PATH="$INSTALL_DIR/dist" exec /usr/local/bin/node "$INSTALL_DIR/dist/app/cli.js" "\$@"
EOF

# Set permissions
echo "Setting up permissions..."
chmod +x "$INSTALL_DIR/node/bin/gymnasticon"
sudo chown -R pi:pi "$INSTALL_DIR"

# Configure Bluetooth
echo "Configuring Bluetooth..."
sudo usermod -a -G bluetooth pi
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)

# Enable and start Bluetooth
echo "Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
sleep 5

# Setup systemd service
echo "Setting up systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=bluetooth.service network.target
Wants=bluetooth.service

[Service]
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
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gymnasticon
ExecStartPre=/bin/sleep 10

[Install]
WantedBy=multi-user.target
EOF

# Restart Bluetooth and start service
echo "Starting services..."
sudo systemctl restart bluetooth
sleep 5
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl restart gymnasticon

echo "=== Gymnasticon Installation Complete ==="
echo "Service status:"
sudo systemctl status gymnasticon --no-pager
