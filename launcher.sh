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

# Start reset monitor if not already running
if ! pgrep -f "monitor_kill.py" > /dev/null; then
    log "Starting monitor_kill.py..."
    python3 "$SCRIPT_DIR/monitor_kill.py" >> "$LOG_FILE" 2>&1 &
fi

# Verify game exists
if [ ! -x "$GAME_ELF" ]; then
    log "ERROR: Game ELF not found or not executable: $GAME_ELF"
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