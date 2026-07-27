#!/bin/bash
# splash-setup.sh — install a simple fbi boot splash and suppress kernel boot text.
set -e

LOG_FILE="/home/pi/arcade.log"
touch "$LOG_FILE" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_SRC="$SCRIPT_DIR/etc/systemd/system/arcade-splash.service"

CMDLINE_FILE="/boot/firmware/cmdline.txt"
if [ ! -f "$CMDLINE_FILE" ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root (try: sudo $0)" >&2
    exit 1
fi

_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

_log "Splash setup starting..."

# Install fbi (framebuffer image viewer)
if ! command -v fbi >/dev/null 2>&1; then
    _log "Installing fbi..."
    apt-get install -y fbi
else
    _log "fbi already installed"
fi

# Install the boot splash service
if [ -f "$SERVICE_SRC" ]; then
    cp "$SERVICE_SRC" /etc/systemd/system/arcade-splash.service
    chmod 644 /etc/systemd/system/arcade-splash.service
    systemctl daemon-reload
    systemctl enable arcade-splash.service
    _log "arcade-splash.service installed and enabled"
else
    _log "WARNING: arcade-splash.service not found at $SERVICE_SRC"
fi

# Copy splash image into the Plymouth theme directory so the Plymouth script can find it.
if [ -f "$SCRIPT_DIR/../splash.png" ]; then
    mkdir -p /usr/share/plymouth/themes/arcade
    cp "$SCRIPT_DIR/../splash.png" /usr/share/plymouth/themes/arcade/splash.png
    _log "Copied splash.png to /usr/share/plymouth/themes/arcade/"
fi

# Suppress boot text in cmdline.txt
if [ ! -f "$CMDLINE_FILE" ]; then
    _log "WARNING: could not find cmdline.txt at $CMDLINE_FILE — skipping kernel quiet patch"
else
    _log "Patching $CMDLINE_FILE..."
    ORIG=$(cat "$CMDLINE_FILE")
    PATCHED="$ORIG"

    # Redirect console=tty1 to tty3 so kernel messages don't show on the arcade display.
    PATCHED=$(echo "$PATCHED" | sed 's/console=tty1/console=tty3/g')

    for FLAG in quiet splash "logo.nologo" "loglevel=3" "vt.global_cursor_default=0"; do
        if ! echo "$PATCHED" | grep -qw "$FLAG"; then
            PATCHED="$PATCHED $FLAG"
        fi
    done

    if [ "$ORIG" != "$PATCHED" ]; then
        cp "$CMDLINE_FILE" "${CMDLINE_FILE}.bak"
        echo "$PATCHED" > "$CMDLINE_FILE"
        _log "cmdline.txt updated (backup: ${CMDLINE_FILE}.bak)"
    else
        _log "cmdline.txt already contains all quiet/splash flags"
    fi
fi

_log "Splash setup complete"
