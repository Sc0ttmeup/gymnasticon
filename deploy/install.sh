# Install Node.js for ARMv6
if ! command -v node > /dev/null || ! command -v npm > /dev/null; then
    echo "Node.js and npm are not installed. Installing for ARMv6..."
    NODE_VERSION="14.21.3"  # Specify your desired Node.js version
    NODE_DISTRO="linux-armv6l"
    NODE_ARCHIVE="node-v$NODE_VERSION-$NODE_DISTRO.tar.xz"
    NODE_URL="https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/$NODE_ARCHIVE"

    # Download Node.js
    echo "Downloading Node.js from $NODE_URL..."
    curl -o $NODE_ARCHIVE $NODE_URL

    # Check if the file is downloaded
    if [ ! -f $NODE_ARCHIVE ]; then
        echo "Failed to download Node.js. Exiting."
        exit 1
    fi

    # Validate the file format
    echo "Validating the Node.js archive..."
    if ! file $NODE_ARCHIVE | grep -q "XZ compressed data"; then
        echo "Invalid Node.js archive format. Exiting."
        rm -f $NODE_ARCHIVE
        exit 1
    fi

    # Extract Node.js
    echo "Extracting Node.js..."
    sudo tar -xJf $NODE_ARCHIVE -C /usr/local --strip-components=1 || {
        echo "Extraction failed. Check the archive file."
        rm -f $NODE_ARCHIVE
        exit 1
    }

    # Clean up
    rm -f $NODE_ARCHIVE
    echo "Node.js installed successfully!"
else
    echo "Node.js and npm are already installed."
fi
