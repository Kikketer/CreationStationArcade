#!/bin/bash
# Run this after any git pull on the Pi to restore executable bits
chmod +x launcher.sh simpleLaunch.sh monitor_kill.py usb-to-gpio.py
find games -name "*.elf" -exec chmod +x {} \;
echo "Executable bits restored."
