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

log "=== Kill-to-menu: syncing code ==="

if [ -d "$SOURCE_DIR/.git" ]; then
    # Git pull in background (don't block return to menu, tolerates no network)
    (
        cd "$SOURCE_DIR"
        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        timeout 15s git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1 || true
        if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse "origin/$BRANCH")
            if [ "$LOCAL" != "$REMOTE" ]; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] Git: updating to origin/$BRANCH" >> "$LOG_FILE"
                git reset --hard "origin/$BRANCH" >> "$LOG_FILE" 2>&1
            fi
        fi
    ) &

    # Rsync waits (foreground) - fast local copy, ensures -run matches source NOW
    log "Syncing source to runtime folder..."
    rsync -a --no-group --no-owner --delete --exclude ".git" --exclude "arcade.log" --exclude ".lgd-*" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    log "Sync complete"
fi

log "=== Kill-to-menu complete ==="
