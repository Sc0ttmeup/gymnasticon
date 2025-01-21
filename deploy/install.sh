#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/var/log/gymnasticon-install.log"
NODE_VERSION="14.x"
NODE_SETUP_URL="https://deb.nodesource.com/setup_${NODE_VERSION}"

# Start logging with sudo to ensure write permissions
exec > >(sudo tee -a $LOG_FILE) 2>&1

# Enhanced helper functions
show_progress() {
    echo "[$1] $2"
    sleep 1
}

handle_error() {
    echo "Error occurred at line $1"
    exit 1
}











    # Enhanced cleanup_locks function
    cleanup_locks() {
        show_progress "Cleanup" "Removing package manager locks..."
        # Wait for any unattended-upgrades to finish
        while sudo lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            show_progress "Waiting" "Package manager is busy, waiting 30 seconds..."
            sleep 30
        done
    
        sudo killall apt apt-get >/dev/null 2>&1 || true
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
        sudo rm -f /var/lib/dpkg/lock*
        sudo rm -f /var/lib/dpkg/lock-frontend
        sudo dpkg --configure -a
    
        # Additional wait to ensure locks are released
        sleep 5
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

# Ensure we're in home directory
cd ~

show_progress "1/8" "Starting installation of Gymnasticon..."

# Clean removal of previous installation
show_progress "2/8" "Removing previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf $INSTALL_DIR
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Clean package manager locks
show_progress "3/8" "Cleaning package manager state..."
cleanup_locks

# System dependencies
show_progress "4/8" "Installing system dependencies..."
for i in {1..3}; do
    if sudo apt-get update && \
       sudo apt-get install -y \
        git \
        bluetooth \
        bluez \
        libbluetooth-dev \
        libudev-dev \
        libusb-1.0-0-dev \
        build-essential \
        curl \
        jq; then
        break
    fi
    show_progress "Retry" "Package installation attempt $i failed, retrying..."
    sleep 5
    cleanup_locks
done
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

    # Configure package.json for ES modules
    jq '. + {"type":"module"}' package.json > package.json.tmp && mv package.json.tmp package.json

    # Configure babel to handle ES modules correctly
    echo '{
      "presets": [
        ["@babel/preset-env", {
          "targets": {
            "node": "14"
          },
          "modules": false
        }]
      ]
    }' > .babelrc

    # Dependencies and build
    show_progress "6/7" "Checking existing installation..."

    # Check if lib/app/cli.js already exists and is valid
    if [ -f "lib/app/cli.js" ] && node -c lib/app/cli.js > /dev/null 2>&1; then
        echo "Valid existing installation found, skipping build process"
    else
        echo "Building from source..."
        # Install global dependencies first
        npm install -g @babel/cli @babel/core

        # Install project dependencies
        npm install --no-audit --no-fund

        # Create necessary directories
        mkdir -p lib/app

        # Install babel dependencies locally
        npm install --save-dev @babel/cli @babel/core @babel/preset-env

        # Run babel build
        NODE_ENV=production npx babel src --out-dir lib --verbose
    fi
# Verify the output
if [ -f "lib/app/cli.js" ]; then
    echo "Build verification successful"
    node -c lib/app/cli.js
else
    echo "Build verification failed"
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