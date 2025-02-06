#!/bin/bash
# Installation script for Gymnasticon on RPiZero with Node 14

set -e

echo "=== Starting Gymnasticon Installation ==="

# Configuration
NODE_VERSION="14.21.3"
NODE_DISTRO="node-v${NODE_VERSION}-linux-armv6l"
NODE_DOWNLOAD_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
INSTALL_DIR="/opt/gymnasticon"
GITHUB_REPO="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"

# Environment setup
export NODE_OPTIONS="--max-old-space-size=512"
export npm_config_build_from_source=true

# Clean previous installations
echo "Cleaning previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"

# System dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y git bluetooth bluez libbluetooth-dev libudev-dev libusb-1.0-0-dev build-essential curl xz-utils

# Node.js installation
echo "Installing Node.js ${NODE_VERSION}..."
cd /tmp
curl -fsSL "$NODE_DOWNLOAD_URL" -o "${NODE_DISTRO}.tar.xz"
tar -xf "${NODE_DISTRO}.tar.xz"
sudo cp -R "${NODE_DISTRO}"/* /usr/local/
sudo ln -sf /usr/local/bin/node /usr/bin/node
sudo ln -sf /usr/local/bin/npm /usr/bin/npm

# Install Gymnasticon
echo "Installing Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
git clone -b "$BRANCH" "$GITHUB_REPO" .

# NPM setup
npm config set unsafe-perm true
npm config set legacy-peer-deps true
npm install

# Build setup
echo "Setting up build environment..."
mkdir -p dist
cp -r src/* dist/

# Create executable
echo "Creating executable wrapper..."
mkdir -p node/bin
cat > node/bin/gymnasticon << EOF
#!/bin/bash
NODE_PATH="$INSTALL_DIR/dist" exec /usr/local/bin/node "$INSTALL_DIR/dist/app/cli.js" "\$@"
EOF
chmod +x node/bin/gymnasticon

# Permissions
sudo chown -R pi:pi "$INSTALL_DIR"
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)

# Service setup
cat <<EOF | sudo tee /etc/systemd/system/gymnasticon.service
[Unit]
Description=Gymnasticon
After=network.target bluetooth.service

[Service]
ExecStart=/usr/bin/node $INSTALL_DIR/dist/app/cli.js
WorkingDirectory=$INSTALL_DIR
Restart=always
User=pi
Environment=NODE_ENV=production
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=gymnasticon

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon

echo "=== Gymnasticon Installation Complete ==="
sudo systemctl status gymnasticon --no-pager
