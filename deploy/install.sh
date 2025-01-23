#!/bin/bash
set -e

# Repository and branch settings
REPO_URL="https://github.com/4o4R/gymnasticon.git"
BRANCH="master"
INSTALL_DIR="/opt/gymnasticon"
LOG_FILE="/var/log/gymnasticon-install.log"
NODE_VERSION="14.x"
NODE_SETUP_URL="https://deb.nodesource.com/setup_${NODE_VERSION}"
SWAP_SIZE=1024
SECONDS=0
TOTAL_STEPS=8

# Start logging with sudo to ensure write permissions
sudo apt-get install -y bc
exec > >(sudo tee -a $LOG_FILE) 2>&1

# Enhanced helper functions with time estimation
show_progress() {
    local step=$1
    local message=$2
    local elapsed=$SECONDS
    
    local step_num
    step_num=$(echo "$step" | grep -o '^[0-9]*' || echo "0")

    if [[ "$step_num" -gt 0 ]]; then
        local progress
        progress=$(echo "scale=2; ($step_num * 100) / $TOTAL_STEPS" | bc)
        # Estimate remaining time based on how many steps remain vs how many have elapsed
        local remaining_time
        if [[ "$step_num" -gt 0 ]]; then
            remaining_time=$(echo "scale=0; ($elapsed * ($TOTAL_STEPS - $step_num)) / $step_num" | bc)
        else
            remaining_time=0
        fi
        echo "[${progress}% - Step $step/$TOTAL_STEPS - Est. ${remaining_time}s remaining] $message"
    else
        echo "[In Progress - Step $step/$TOTAL_STEPS] $message"
    fi
    echo "Current runtime: ${elapsed}s"
}

show_build_progress() {
    local pid=$1
    local step=$2
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r[Step %s - Running for %ds] " "$step" "$count"
        for ((i=0; i<count%4; i++)); do 
            printf "." 
        done
        sleep 1
        ((count++))
    done
    echo
}

npm_install_with_timeout() {
    # 5-minute (300s) timeout, can adjust if needed
    timeout 300 "$@" || {
        echo "Command timed out, retrying..."
        sleep 5
        timeout 300 "$@"
    }
}

handle_error() {
    echo "Error occurred at line $1"
    cleanup_swap
    exit 1
}

setup_swap() {
    show_progress "Setup" "Creating temporary swap file..."
    
    # PROACTIVE CLEANUP: remove any leftover swapfile that might be busy
    if [ -f /swapfile ]; then
        echo "Detected existing /swapfile. Attempting to remove it..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi

    # Now safely create a fresh swapfile
    sudo fallocate -l ${SWAP_SIZE}M /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
}

cleanup_swap() {
    if [ -f /swapfile ]; then
        show_progress "Cleanup" "Removing temporary swap file..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi
}

cleanup_locks() {
    show_progress "Cleanup" "Removing package manager locks..."
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
        sudo usermod -a -G bluetooth "$USER"
    fi
    if ! groups | grep -q dialout; then
        sudo usermod -a -G dialout "$USER"
    fi
}

verify_service() {
    for i in {1..3}; do
        if systemctl is-active --quiet gymnasticon; then
            return 0
        fi
        echo "Waiting for service to start (attempt $i/3)..."
        sleep 10
    done
    echo "Service failed to start properly"
    journalctl -u gymnasticon -n 50
    exit 1
}

trap 'handle_error $LINENO' ERR

# Ensure we're in home directory
cd ~

show_progress "1/8" "Starting installation of Gymnasticon..."

# Clean removal of previous installation
show_progress "2/8" "Removing previous installations..."
sudo systemctl stop gymnasticon 2>/dev/null || true
sudo systemctl disable gymnasticon 2>/dev/null || true
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /etc/systemd/system/gymnasticon.service
sudo systemctl daemon-reload

# Clean package manager locks
show_progress "3/8" "Cleaning package manager state..."
cleanup_locks

# System dependencies
show_progress "4.1/8" "Updating package lists..."
sudo apt-get update

show_progress "4.2/8" "Installing system packages..."
for i in {1..3}; do
    if sudo apt-get install -y \
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

# Configure ANT+ USB rules
show_progress "4.3/8" "Configuring ANT+ USB rules..."
sudo tee /etc/udev/rules.d/51-garmin-usb.rules > /dev/null <<EOL
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1008", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1009", MODE="0666"
EOL

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Node.js setup
show_progress "5/8" "Setting up Node.js environment..."
check_node_version

# Create installation directory with proper permissions
show_progress "6.1/8" "Setting up Gymnasticon..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown "$USER:$USER" "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# Repository setup
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" .

# Dependencies and build
show_progress "6.2/8" "Configuring build environment..."
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=256"

# Configure npm
npm config set registry https://registry.npmjs.org/
npm config set unsafe-perm true
npm config set legacy-peer-deps true

# Setup swap
setup_swap

show_progress "6.3/8" "Installing Babel tools..."
# Install Babel globally (could do locally if you prefer)
npm_install_with_timeout npm install -g @babel/cli @babel/core @babel/plugin-transform-modules-commonjs --no-audit --no-fund --unsafe-perm --legacy-peer-deps &
BABEL_PID=$!
show_build_progress $BABEL_PID "6.3/8"

show_progress "6.4/8" "Installing project dependencies..."
# 1) production dependencies
npm_install_with_timeout npm install --no-audit --no-fund --production --unsafe-perm --build-from-source --jobs=1 --legacy-peer-deps &
NPM_PID=$!
show_build_progress $NPM_PID "6.4/8"

# 2) dev dependencies
npm_install_with_timeout npm install --no-audit --no-fund --only=dev --unsafe-perm --build-from-source --jobs=1 --legacy-peer-deps &
NPM_DEV_PID=$!
show_build_progress $NPM_DEV_PID "6.4/8"

# Clean npm cache
npm cache clean --force

# Create necessary directories
mkdir -p lib/app

show_progress "6.5/8" "Configuring Babel..."
# Configure babel with proper module transformation
cat > .babelrc <<EOF
{
  "presets": [
    ["@babel/preset-env", {
      "targets": {
        "node": "14"
      },
      "modules": "commonjs"
    }]
  ],
  "plugins": [
    "@babel/plugin-transform-modules-commonjs"
  ]
}
EOF

show_progress "6.55/8" "Switching package.json to commonjs..."
# Set package type to commonjs
jq '. + {"type": "commonjs"}' package.json > package.json.tmp && mv package.json.tmp package.json

show_progress "6.6/8" "Building project..."
# Run babel build
NODE_ENV=production npx babel src --out-dir lib --verbose &
BABEL_BUILD_PID=$!
show_build_progress $BABEL_BUILD_PID "6.6/8"

# Cleanup swap
cleanup_swap

# Verify the output
if [ -f "lib/app/cli.js" ]; then
    show_progress "7.1/8" "Build verification successful"
    node -c lib/app/cli.js
else
    show_progress "7.1/8" "Build verification failed"
    ls -la lib/app/
    ls -la src/app/
    exit 1
fi

# Set permissions
sudo chown -R "$USER:$USER" "$INSTALL_DIR"
validate_permissions

show_progress "7.2/8" "Configuring service..."
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
User=$USER
Group=$USER
ExecStart=/usr/local/bin/node $INSTALL_DIR/lib/app/cli.js
RestartSec=1
Restart=always
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOL

show_progress "8/8" "Starting service..."
# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable gymnasticon
sudo systemctl start gymnasticon
verify_service

show_progress "Complete" "Gymnasticon installation finished in ${SECONDS}s!"
