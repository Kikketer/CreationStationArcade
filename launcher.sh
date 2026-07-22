#!/bin/bash
# launcher.sh - Single-game ELF kiosk launcher for Pi 3 / Pi Zero
# Runs one configured ELF game directly, no menu.
# Reset button (via monitor_kill.py) kills and relaunches this script.

LOG_FILE="/home/pi/arcade.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# CONFIGURE YOUR GAME HERE (or set SINGLE_GAME_NAME env var)
GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}"
GAME_ELF="$SCRIPT_DIR/games/${GAME_NAME}.elf"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Launcher start: game=$GAME_NAME ==="

# Kill splash screen if running from previous restart
pkill -f fbi 2>/dev/null || true

# Always kill stale usb-to-gpio processes and re-setup the virtual keyboard.
# This ensures /sd/arcade.cfg has the correct eventX on every launch (including after reset).
pkill -f "usb-to-gpio.py" 2>/dev/null || true
sleep 2
log "Starting usb-to-gpio.py gamepad reader..."
python3 "$SCRIPT_DIR/usb-to-gpio.py" >> "$LOG_FILE" 2>&1 &

# If we're in keyboard mode, wait for the virtual keyboard to appear and update
# /sd/arcade.cfg before the ELF starts reading it.
if grep -q '^SCAN_CODES=/dev/input' /sd/arcade.cfg 2>/dev/null; then
    VKB_READY=0
    for i in {1..20}; do
        SCAN_PATH=$(grep "^SCAN_CODES=" /sd/arcade.cfg 2>/dev/null | cut -d= -f2)
        if [ -e "$SCAN_PATH" ] && [ -r "/sys/class/input/$(basename "$SCAN_PATH")/device/name" ] \
                && grep -q "MCArcade Virtual Keyboard" "/sys/class/input/$(basename "$SCAN_PATH")/device/name" 2>/dev/null; then
            VKB_READY=1
            break
        fi
        sleep 0.5
    done
    if [ "$VKB_READY" -eq 0 ]; then
        log "WARNING: Virtual keyboard did not become ready in time; SCAN_CODES may be stale."
    fi
    log "Virtual keyboard ready. SCAN_CODES=$(grep "^SCAN_CODES" /sd/arcade.cfg 2>/dev/null | cut -d= -f2)"
else
    # GPIO mode: the usb-to-gpio.py reader will drive physical pins; give it a moment to start.
    sleep 1
    log "GPIO mode: usb-to-gpio.py should be driving pins from /sd/arcade.cfg"
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
# Suppress TTY so keypresses don't bleed through as text behind the game
setterm -cursor off 2>/dev/null || true
stty -echo 2>/dev/null || true
echo -e '\033[?25l\033[2J\033[H' > /dev/tty1 2>/dev/null || true
"$RUNNER" "$GAME_ELF" >> "$LOG_FILE" 2>&1
log "Game exited."