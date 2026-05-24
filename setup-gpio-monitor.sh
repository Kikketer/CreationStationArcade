#!/bin/bash
# setup-gpio-monitor.sh - Install gpio-monitor as systemd service

set -e

SERVICE_NAME="gpio-monitor"
SERVICE_FILE="/home/pi/CreationStationArcade/gpio-monitor.service"
RUN_DIR="/home/pi/CreationStationArcade-run"

echo "=== Installing GPIO Monitor Service ==="

# Check if service file exists
if [ ! -f "$SERVICE_FILE" ]; then
    echo "ERROR: Service file not found at $SERVICE_FILE"
    exit 1
fi

# Copy service file to systemd
sudo cp "$SERVICE_FILE" /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable $SERVICE_NAME

echo "=== GPIO Monitor Service Installed ==="
echo "Commands:"
echo "  sudo systemctl start $SERVICE_NAME   # Start now"
echo "  sudo systemctl stop $SERVICE_NAME    # Stop"
echo "  sudo systemctl status $SERVICE_NAME  # Check status"
echo "  tail -f /home/pi/arcade.log          # View logs"
echo ""
echo "Starting service now..."
sudo systemctl start $SERVICE_NAME

sleep 2
sudo systemctl status $SERVICE_NAME --no-pager
