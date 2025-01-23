# WSL Build Process for Gymnasticon

## 1. Initial Setup and Node Installation
```bash
# Install NVM and Node 14
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 14
nvm use 14

# Verify Node version
node -v  # Should show v14.x.x

2. Clone and Configure Build Environment
# Clone repository
git clone https://github.com/4o4R/gymnasticon.git
cd gymnasticon

# Set build environment variables
export npm_config_build_from_source=true
export CFLAGS="-O1"
export CXXFLAGS="-O1"
export npm_config_jobs=1
export NODE_OPTIONS="--max-old-space-size=256"

# Configure npm
npm config set unsafe-perm true
npm config set legacy-peer-deps true
3. Install Dependencies and Build
# Install Babel and core dependencies
npm install \
  @babel/cli \
  @babel/core \
  @babel/plugin-transform-modules-commonjs \
  @babel/preset-env \
  --no-save --build-from-source --unsafe-perm

# Install production dependencies
npm install --production --unsafe-perm --build-from-source

# Configure Babel
echo '{
  "presets": [
    ["@babel/preset-env", {
      "targets": { "node": "14" },
      "modules": "commonjs"
    }]
  ],
  "plugins": [
    "@babel/plugin-transform-modules-commonjs"
  ]
}' > .babelrc

# Set package type
jq '. + {"type":"commonjs"}' package.json > package.json.tmp && mv package.json.tmp package.json

# Build project
npx babel src --out-dir lib


4. Create Distributable Image
# Install required tools
sudo apt-get update
sudo apt-get install -y kpartx

# Download and extract Raspbian
wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2023-05-03/2023-05-03-raspios-bullseye-armhf-lite.img.xz
xz -d 2023-05-03-raspios-bullseye-armhf-lite.img.xz

# Set up mount points and map partitions
sudo mkdir -p /mnt/pi
sudo kpartx -av 2023-05-03-raspios-bullseye-armhf-lite.img
sudo mount /dev/mapper/loop1p2 /mnt/pi

# Copy built files
sudo mkdir -p /mnt/pi/opt/gymnasticon
sudo cp -r lib package.json node_modules /mnt/pi/opt/gymnasticon/

# Create service file
sudo tee /mnt/pi/etc/systemd/system/gymnasticon.service <<EOF
[Unit]
Description=Gymnasticon
After=bluetooth.target
Requires=bluetooth.target

[Service]
Type=simple
Environment=PATH=/usr/local/bin:/opt/gymnasticon/node_modules/.bin
WorkingDirectory=/opt/gymnasticon
User=pi
Group=pi
ExecStart=/usr/local/bin/node /opt/gymnasticon/lib/app/cli.js
Restart=always
RestartSec=1
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Cleanup and unmount
sudo umount /mnt/pi
sudo kpartx -d 2023-05-03-raspios-bullseye-armhf-lite.img



5. Verify Build
# Check built files
ls -la lib/app/cli.js


The resulting image file can be flashed to an SD card using tools like balenaEtcher.


This creates a well-structured markdown file in the deploy directory with:
1. Clear section headers
2. Properly formatted code blocks
3. Step-by-step instructions
4. All necessary commands
5. Verification steps
6. Final deployment instructions

The file will be ready to commit to the repository and serve as a reference for future builds.

Copy and Paste block into WSL Terminal:
# Single command block for Gymnasticon build
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \
source ~/.bashrc && \
nvm install 14 && \
nvm use 14 && \
git clone https://github.com/4o4R/gymnasticon.git && \
cd gymnasticon && \
export npm_config_build_from_source=true && \
export CFLAGS="-O1" && \
export CXXFLAGS="-O1" && \
export npm_config_jobs=1 && \
export NODE_OPTIONS="--max-old-space-size=256" && \
npm config set unsafe-perm true && \
npm config set legacy-peer-deps true && \
npm install @babel/cli @babel/core @babel/plugin-transform-modules-commonjs @babel/preset-env --no-save --build-from-source --unsafe-perm && \
npm install --production --unsafe-perm --build-from-source && \
echo '{"presets":[["@babel/preset-env",{"targets":{"node":"14"},"modules":"commonjs"}]],"plugins":["@babel/plugin-transform-modules-commonjs"]}' > .babelrc && \
jq '. + {"type":"commonjs"}' package.json > package.json.tmp && mv package.json.tmp package.json && \
npx babel src --out-dir lib && \
sudo apt-get update && \
sudo apt-get install -y kpartx && \
wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2023-05-03/2023-05-03-raspios-bullseye-armhf-lite.img.xz && \
xz -d 2023-05-03-raspios-bullseye-armhf-lite.img.xz && \
sudo mkdir -p /mnt/pi && \
sudo kpartx -av 2023-05-03-raspios-bullseye-armhf-lite.img && \
sudo mount /dev/mapper/loop1p2 /mnt/pi && \
sudo mkdir -p /mnt/pi/opt/gymnasticon && \
sudo cp -r lib package.json node_modules /mnt/pi/opt/gymnasticon/ && \
sudo tee /mnt/pi/etc/systemd/system/gymnasticon.service <<EOF
[Unit]
Description=Gymnasticon
After=bluetooth.target
Requires=bluetooth.target

[Service]
Type=simple
Environment=PATH=/usr/local/bin:/opt/gymnasticon/node_modules/.bin
WorkingDirectory=/opt/gymnasticon
User=pi
Group=pi
ExecStart=/usr/local/bin/node /opt/gymnasticon/lib/app/cli.js
Restart=always
RestartSec=1
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

sudo umount /mnt/pi && \
sudo kpartx -d 2023-05-03-raspios-bullseye-armhf-lite.img && \
ls -la lib/app/cli.js

\\wsl$\Ubuntu\home\YourWSLUsername\gymnasticon
or
C:\Users\YourUsername\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\rootfs\home\YourWSLUsername\gymnasticon\2023-05-03-raspios-bullseye-armhf-lite.img
