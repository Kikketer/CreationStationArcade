#!/bin/bash

set -e

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEME_SRC="$SCRIPT_DIR/usr/share/plymouth/themes/arcade"
THEME_DEST="/usr/share/plymouth/themes/arcade"
IMAGE_SRC="/home/pi/CreationStationArcade/media/MadeArcadeBoot.png"

CMDLINE_FILE="/boot/firmware/cmdline.txt"
if [ ! -f "$CMDLINE_FILE" ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root (try: sudo $0)" >&2
    exit 1
fi

if [ ! -d "$THEME_SRC" ]; then
    echo "ERROR: missing theme source at $THEME_SRC" >&2
    exit 1
fi

if [ ! -f "$IMAGE_SRC" ]; then
    echo "ERROR: missing splash image at $IMAGE_SRC" >&2
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Splash setup: starting" >> "$LOG_FILE"

# Install Plymouth and the script module
echo "Installing Plymouth..."
apt-get install -y plymouth plymouth-themes

# Copy the arcade theme
mkdir -p "$THEME_DEST"
cp "$THEME_SRC/arcade.plymouth" "$THEME_DEST/"
cp "$THEME_SRC/arcade.script" "$THEME_DEST/"
cp "$IMAGE_SRC" "$THEME_DEST/MadeArcadeBoot.png"
chmod 644 "$THEME_DEST/"*

# Set the arcade theme as default
plymouth-set-default-theme arcade

# Rebuild initramfs so Plymouth is included in early boot
echo "Rebuilding initramfs (this may take a minute)..."
update-initramfs -u

echo "Plymouth arcade theme installed."

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
