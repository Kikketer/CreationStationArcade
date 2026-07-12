#!/bin/bash
# launcher.sh - Single-game ELF kiosk launcher for Pi 3
# Runs one configured ELF game directly, no menu.
# Reset button (via monitor_kill.py) kills and relaunches this script.

LOG_FILE="/home/pi/arcade.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# CONFIGURE YOUR GAME HERE (or set SINGLE_GAME_NAME env var)
GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}"
GAME_ELF="$SCRIPT_DIR/games/${GAME_NAME}.elf"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Launcher start: game=$GAME_NAME ==="

# Set up virtual keyboard synchronously so /sd/arcade.cfg has correct eventX
# before the elf starts. The --setup-only flag forks a child to keep the
# uinput device alive and returns immediately.
if ! pgrep -f "usb-to-gpio.py" > /dev/null; then
    log "Setting up virtual keyboard (usb-to-gpio.py --setup-only)..."
    sudo python3 "$SCRIPT_DIR/usb-to-gpio.py" --setup-only >> "$LOG_FILE" 2>&1
    log "Virtual keyboard setup done. SCAN_CODES=$(grep SCAN_CODES /sd/arcade.cfg 2>/dev/null | cut -d= -f2)"
    # Now start the full gamepad reader in background
    log "Starting usb-to-gpio.py gamepad reader..."
    sudo python3 "$SCRIPT_DIR/usb-to-gpio.py" >> "$LOG_FILE" 2>&1 &
fi

# Start reset monitor if not already running
if ! pgrep -f "monitor_kill.py" > /dev/null; then
    log "Starting monitor_kill.py..."
    python3 "$SCRIPT_DIR/monitor_kill.py" >> "$LOG_FILE" 2>&1 &
fi

# Verify game exists
if [ ! -x "$GAME_ELF" ]; then
    log "ERROR: Game ELF not found or not executable: $GAME_ELF"
    log "Available files in games/:"
    ls "$SCRIPT_DIR/games/" >> "$LOG_FILE" 2>&1 || true
    log "Sleeping 30s before retry..."
    sleep 30
    exit 1
fi

RUNNER="$SCRIPT_DIR/simpleLaunch.sh"
if [ ! -x "$RUNNER" ]; then
    log "ERROR: simpleLaunch.sh missing or not executable"
    exit 1
fi

log "Launching game: $GAME_ELF"
"$RUNNER" "$GAME_ELF" >> "$LOG_FILE" 2>&1
log "Game exited."