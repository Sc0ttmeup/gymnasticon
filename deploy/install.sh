# Replace the final service verification block with:
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

# Then use it after starting the service:
sudo systemctl start gymnasticon
verify_service
