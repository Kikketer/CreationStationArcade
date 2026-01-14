#!/bin/bash

set -e

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ALSA_BASE_CONF="$SCRIPT_DIR/etc/modprobe.d/alsa-base.conf"
SOURCE_VC4_HDMI_CONF="$SCRIPT_DIR/usr/share/alsa/cards/vc4-hdmi.conf"

TARGET_ALSA_BASE_CONF="/etc/modprobe.d/alsa-base.conf"
TARGET_VC4_HDMI_CONF="/usr/share/alsa/cards/vc4-hdmi.conf"

BACKUP_ALSA_BASE_CONF="/etc/modprobe.d/alsa-base.conf_Arcade.bak"
BACKUP_VC4_HDMI_CONF="/usr/share/alsa/cards/vc4-hdmi.conf_Arcade.bak"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root (try: sudo $0)" >&2
    exit 1
fi

if [ ! -f "$SOURCE_ALSA_BASE_CONF" ]; then
    echo "ERROR: missing $SOURCE_ALSA_BASE_CONF" >&2
    exit 1
fi

if [ ! -f "$SOURCE_VC4_HDMI_CONF" ]; then
    echo "ERROR: missing $SOURCE_VC4_HDMI_CONF" >&2
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] HDMI audio fix: installing ALSA config overrides" >> "$LOG_FILE"

mkdir -p "$(dirname "$TARGET_ALSA_BASE_CONF")"
mkdir -p "$(dirname "$TARGET_VC4_HDMI_CONF")"

if [ -f "$TARGET_ALSA_BASE_CONF" ] && [ ! -f "$BACKUP_ALSA_BASE_CONF" ]; then
    cp "$TARGET_ALSA_BASE_CONF" "$BACKUP_ALSA_BASE_CONF"
fi

if [ -f "$TARGET_VC4_HDMI_CONF" ] && [ ! -f "$BACKUP_VC4_HDMI_CONF" ]; then
    cp "$TARGET_VC4_HDMI_CONF" "$BACKUP_VC4_HDMI_CONF"
fi

cp "$SOURCE_ALSA_BASE_CONF" "$TARGET_ALSA_BASE_CONF"
cp "$SOURCE_VC4_HDMI_CONF" "$TARGET_VC4_HDMI_CONF"

chmod 644 "$TARGET_ALSA_BASE_CONF" "$TARGET_VC4_HDMI_CONF" 2>/dev/null || true

echo "HDMI audio fix installed." 
echo "Backups (if created):"
echo "  $BACKUP_ALSA_BASE_CONF"
echo "  $BACKUP_VC4_HDMI_CONF"
echo "Please reboot for changes to take effect." 
