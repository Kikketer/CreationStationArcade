#!/bin/bash
# kill-to-menu.sh - GPIO reset button handler for Chromium kiosk mode
# Kills Chromium and Node server, lets xinitrc restart everything

LOG_FILE="/home/pi/arcade.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# If already in -run folder, use it directly, otherwise append -run
if [[ "$SCRIPT_DIR" == *"-run" ]]; then
    RUN_DIR="$SCRIPT_DIR"
else
    RUN_DIR="${SCRIPT_DIR}-run"
fi
SOURCE_DIR="${CSA_SOURCE_DIR:-${RUN_DIR%-run}}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Kill-to-menu triggered ==="

# Kill only GAME Chromium (launched for /play), leave menu running
log "Killing game Chromium..."
pkill -f "chromium.*localhost:3000/play" 2>/dev/null || true
# Also kill by PID file if exists
kill $(cat /tmp/arcade-game-chromium.pid 2>/dev/null) 2>/dev/null || true
rm -f /tmp/arcade-game-chromium.pid

# Note: We do NOT kill the menu Chromium or Node server - they stay running!
# This gives "instant" return to menu since it was never closed

sleep 1

log "=== Kill-to-menu complete (xinitrc will restart) ==="

# Exit immediately so xinitrc can restart Chromium quickly
# Git sync happens in background (may take time on slow wifi)
(
    if [ -d "$SOURCE_DIR/.git" ]; then
        cd "$SOURCE_DIR"
        timeout 30s git fetch origin chromium-kiosk >/dev/null 2>&1 || true
        if git rev-parse --verify origin/chromium-kiosk >/dev/null 2>&1; then
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse origin/chromium-kiosk)
            if [ "$LOCAL" != "$REMOTE" ]; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] Git: new commits, updating..." >> "$LOG_FILE"
                git reset --hard origin/chromium-kiosk >/dev/null 2>&1
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] Git: updated, will sync next restart" >> "$LOG_FILE"
            fi
        fi
    fi
) &

# Exit - the .xinitrc loop will restart Chromium immediately
