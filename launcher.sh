#!/bin/bash
# launcher.sh - Single-game ELF kiosk launcher for Pi 3
# Runs one configured ELF game directly, no menu.
# Reset button (via monitor_kill.py) kills and relaunches the same game.

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR%-run}"}"

# CONFIGURE YOUR GAME HERE (or set SINGLE_GAME_NAME env var)
GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}"
GAME_ELF="$RUN_DIR/games/${GAME_NAME}.elf"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== Launcher start: game=$GAME_NAME ==="

# Sync from source repo if available
if [ -d "$SOURCE_DIR/.git" ]; then
    log "Syncing from $SOURCE_DIR to $RUN_DIR"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --no-perms --no-owner --no-group --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    else
        cp -a "$SOURCE_DIR"/. "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    fi
    chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/simpleLaunch.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
    find "$RUN_DIR/games" -name "*.elf" -exec chmod +x {} \; 2>/dev/null || true
    log "Sync complete."
else
    log "WARNING: Source repo not found at $SOURCE_DIR; starting without sync"
fi

# Pull from git in background (non-blocking, tolerates no network)
if [ -x "$RUN_DIR/pullFromGit.sh" ]; then
    "$RUN_DIR/pullFromGit.sh" &
fi

# Start reset monitor if not already running
if ! pgrep -f "monitor_kill.py" > /dev/null; then
    log "Starting monitor_kill.py..."
    python3 "$RUN_DIR/monitor_kill.py" >> "$LOG_FILE" 2>&1 &
fi

# Verify game exists
if [ ! -x "$GAME_ELF" ]; then
    log "ERROR: Game ELF not found or not executable: $GAME_ELF"
    exit 1
fi

RUNNER="$RUN_DIR/simpleLaunch.sh"
if [ ! -x "$RUNNER" ]; then
    log "ERROR: simpleLaunch.sh missing or not executable"
    exit 1
fi

# Launch loop — monitor_kill.py kills the elf and relaunches this script via autostart
log "Launching game: $GAME_ELF"
"$RUNNER" "$GAME_ELF" >> "$LOG_FILE" 2>&1
log "Game exited."