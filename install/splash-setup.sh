#!/bin/bash

set -e

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_SRC="$SCRIPT_DIR/etc/systemd/system/arcade-splash.service"
SERVICE_DEST="/etc/systemd/system/arcade-splash.service"

CMDLINE_FILE="/boot/firmware/cmdline.txt"
if [ ! -f "$CMDLINE_FILE" ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root (try: sudo $0)" >&2
    exit 1
fi

if [ ! -f "$SERVICE_SRC" ]; then
    echo "ERROR: missing $SERVICE_SRC" >&2
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Splash setup: starting" >> "$LOG_FILE"

# Install fbi (framebuffer image viewer)
if ! command -v fbi >/dev/null 2>&1; then
    echo "Installing fbi..."
    apt-get install -y fbi
fi

# Install the systemd service
cp "$SERVICE_SRC" "$SERVICE_DEST"
chmod 644 "$SERVICE_DEST"
systemctl daemon-reload
systemctl enable arcade-splash.service

echo "arcade-splash.service installed and enabled."

# Patch /boot/firmware/cmdline.txt to suppress boot text
if [ ! -f "$CMDLINE_FILE" ]; then
    echo "WARNING: could not find cmdline.txt at $CMDLINE_FILE — skipping kernel quiet patch" >&2
else
    echo "Patching $CMDLINE_FILE..."
    ORIG=$(cat "$CMDLINE_FILE")
    PATCHED="$ORIG"

    # Redirect console=tty1 to tty3 so kernel messages don't bleed onto the arcade display
    PATCHED=$(echo "$PATCHED" | sed 's/console=tty1/console=tty3/g')

    # Add each flag only if not already present
    for FLAG in quiet splash "logo.nologo" "loglevel=3" "vt.global_cursor_default=0"; do
        if ! echo "$PATCHED" | grep -qw "$FLAG"; then
            PATCHED="$PATCHED $FLAG"
        fi
    done

    if [ "$ORIG" != "$PATCHED" ]; then
        cp "$CMDLINE_FILE" "${CMDLINE_FILE}.bak"
        echo "$PATCHED" > "$CMDLINE_FILE"
        echo "cmdline.txt updated (backup: ${CMDLINE_FILE}.bak)"
    else
        echo "cmdline.txt already contains all quiet/splash flags, no change needed."
    fi
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Splash setup: complete" >> "$LOG_FILE"
echo ""
echo "Done. Please reboot to apply changes."
