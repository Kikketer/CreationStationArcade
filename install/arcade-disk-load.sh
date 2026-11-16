#!/bin/bash
# arcade-disk-load.sh — "insert a floppy, press reset" game loading.
# Run as root (through sudo) by the GPIO reset helper on every reset press.
# USB floppy drives don't announce a disk being inserted, so the disk is only
# read when someone presses reset.
#
# Exit 0: the disk held a new game and it was loaded; the helper must NOT also
#         send the soft-reset key.
# Exit 1: no floppy drive, no disk, or the disk holds the game that's already
#         active; the helper sends the normal soft reset.
#
# The disk uses the same layout as a USB stick (the compiler's .tar.gz at the
# root, or an arcade-game/ folder); arcade-usb-update.sh does the actual
# validation and install.
#
# /etc/arcade-usb-update.conf may set FLOPPY_DEV (e.g. /dev/sda) to skip
# auto-detection of the USB floppy drive.

set -u

CONF="${ARCADE_USB_CONF:-/etc/arcade-usb-update.conf}"
FLOPPY_DEV=""
[ -f "$CONF" ] && . "$CONF"

UPDATER="${ARCADE_USB_UPDATER:-/usr/local/sbin/arcade-usb-update.sh}"
LOADING_FILE="${ARCADE_LOADING_FILE:-/tmp/creationstation_disk_loading}"
PIDFILE="${ARCADE_GAME_PIDFILE:-/tmp/creationstation_current_game.pid}"
LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
export ARCADE_USB_CONF="$CONF" ARCADE_GAME_PIDFILE="$PIDFILE" ARCADE_LOG="$LOG_FILE"
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

if ! "$UPDATER" --check "$DEV"; then
    exit 1
fi

# Tell launcher.sh to show the loading screen instead of restarting the old
# game, then stop the old game while the drive reads the disk.
echo "$$" > "$LOADING_FILE"
chmod 644 "$LOADING_FILE" 2>/dev/null || true
trap 'rm -f "$LOADING_FILE"' EXIT

GAME_PID=""
[ -f "$PIDFILE" ] && GAME_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
    log "stopping running Game (pid $GAME_PID) to read the disk"
    kill "$GAME_PID" 2>/dev/null || true
fi

log "reading game from $DEV"
if "$UPDATER" "$DEV"; then
    log "disk load finished"
else
    log "disk load failed; the previous game will restart"
fi
# The old game was stopped either way, so the reset has already happened.
exit 0
