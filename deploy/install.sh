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

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo apt-get remove -y nodejs nodejs-doc || true

# System updates and dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils

# Node.js installation for ARMv6 (RPiZero)
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

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

# NPM configuration and installation
echo "Setting up npm and installing dependencies..."
cd "$INSTALL_DIR"
npm config set unsafe-perm true
npm config set legacy-peer-deps true
npm config set audit false
npm install

# Create dist directory and build
echo "Building Gymnasticon..."
mkdir -p dist
./node_modules/.bin/babel src --out-dir dist --copy-files

# Verify build
if [ ! -d "$INSTALL_DIR/dist" ]; then
    echo "ERROR: Build failed - 'dist' directory not found"
    exit 1
fi

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
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)

# Setup systemd service
echo "Setting up systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=network.target bluetooth.service

[Service]
ExecStart=/usr/bin/node /opt/gymnasticon/dist/app/cli.js
WorkingDirectory=/opt/gymnasticon
Restart=always
User=pi
Group=pi
Environment=NODE_ENV=production
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=gymnasticon
ExecStartPre=/bin/sleep 5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "Starting Gymnasticon service..."
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl restart gymnasticon

echo "=== Gymnasticon Installation Complete ==="
echo "Service status:"
sudo systemctl status gymnasticon --no-pager
