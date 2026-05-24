#!/bin/bash
# setup-gamepad.sh - Install dependencies for GPIO virtual gamepad

LOG_FILE="/home/pi/arcade.log"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Setting up GPIO Virtual Gamepad..." | tee -a "$LOG_FILE"

# Install pip3 if not present
if ! command -v pip3 &> /dev/null; then
    echo "Installing pip3..." | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y python3-pip
fi

# Install uhid Python module
echo "Installing uhid module..." | tee -a "$LOG_FILE"
sudo pip3 install uhid

# Ensure uhid kernel module is loaded
echo "Loading uhid kernel module..." | tee -a "$LOG_FILE"
sudo modprobe uhid

# Enable uhid module on boot
echo "uhid" | sudo tee /etc/modules-load.d/uhid.conf

# Copy files to runtime folder
RUN_DIR="/home/pi/CreationStationArcade-run"
SOURCE_DIR="/home/pi/CreationStationArcade"

cp "$SOURCE_DIR/gpio-gamepad.py" "$RUN_DIR/"
cp "$SOURCE_DIR/arcade.cfg" "$RUN_DIR/"

# Install systemd service
sudo cp "$SOURCE_DIR/gpio-gamepad.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gpio-gamepad.service
sudo systemctl start gpio-gamepad.service

echo "[$(date +'%Y-%m-%d %H:%M:%S')] GPIO Gamepad setup complete!" | tee -a "$LOG_FILE"
echo "Check status with: sudo systemctl status gpio-gamepad" | tee -a "$LOG_FILE"
echo "View gamepads with: ls /dev/input/js*" | tee -a "$LOG_FILE"
