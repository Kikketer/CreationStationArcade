#!/bin/bash
# arcade-disk-load.sh — "insert a floppy, press reset" game loading.
# Run as root (through sudo) by reset-single-game.sh on every reset press.
# USB floppy drives don't announce a disk being inserted, so the disk is only
# read when someone presses reset.
#
#   --check: fast probe — exit 0 if the drive has a disk holding a NEW game,
#            so the caller knows to show the loading screen before the full
#            read. Exits 1 for no drive / no disk / same game.
#   (no arg): read the disk and install the game via arcade-usb-update.sh.
#
# Exit 0 on the full run means a game was installed (or attempted and failed —
# the caller restarts with whatever is active either way); exit 1 means
# nothing disk-related happened and the reset is a plain reset.
#
# The disk uses the USB-stick layout (*.js / *.js.gz at the root, or an
# arcade-games/ folder); arcade-usb-update.sh does the actual validation and
# install into the persistent games dir.
#
# /etc/arcade-usb-update.conf may set FLOPPY_DEV (e.g. /dev/sda) to skip
# auto-detection of the USB floppy drive.

set -u

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
fi

CONF="${ARCADE_USB_CONF:-/etc/arcade-usb-update.conf}"
FLOPPY_DEV=""
[ -f "$CONF" ] && . "$CONF"

UPDATER="${ARCADE_USB_UPDATER:-/usr/local/sbin/arcade-usb-update.sh}"
LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
export ARCADE_USB_CONF="$CONF" ARCADE_LOG="$LOG_FILE"
# A floppy either mounts right away or there's no readable disk; don't stall
# the reset button waiting for one.
export ARCADE_MOUNT_TRIES="${ARCADE_MOUNT_TRIES:-2}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] disk-load: $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] disk-load: $*" >> "$LOG_FILE" 2>/dev/null || true
}

# USB floppy drives report the UFI mass-storage subclass, which udev exposes
# as ID_TYPE=floppy.
find_floppy() {
    if [ -n "$FLOPPY_DEV" ]; then
        echo "$FLOPPY_DEV"
        return
    fi
    local sys dev
    for sys in /sys/block/sd*; do
        [ -e "$sys" ] || continue
        dev="/dev/${sys##*/}"
        if udevadm info --query=property --name="$dev" 2>/dev/null | grep -qxE 'ID_TYPE=floppy|ID_DRIVE_FLOPPY=1'; then
            echo "$dev"
            return
        fi
    done
}

DEV="$(find_floppy)"
if [ -z "$DEV" ]; then
    log "no USB floppy drive found; normal reset"
    exit 1
fi

if [ ! -d "$DEV" ]; then
    if [ ! -b "$DEV" ]; then
        log "$DEV is not a block device; normal reset"
        exit 1
    fi
    # Opening an empty drive fails (no medium), so size 0 means no disk.
    SIZE="$(blockdev --getsize64 "$DEV" 2>/dev/null || echo 0)"
    if [ "${SIZE:-0}" -le 0 ]; then
        log "no disk in $DEV; normal reset"
        exit 1
    fi
    # Floppies are normally unpartitioned, but a partitioned disk works too.
    [ -b "${DEV}1" ] && DEV="${DEV}1"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    exec "$UPDATER" --check "$DEV"
fi

if ! "$UPDATER" --check "$DEV"; then
    exit 1
fi

log "reading game from $DEV"
if "$UPDATER" "$DEV"; then
    log "disk load finished"
    exit 0
fi
log "disk load failed"
exit 1
