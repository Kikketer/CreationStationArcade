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

# Kill Chromium and Node server
log "Killing Chromium and Node server..."
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
pkill -f "node server.js" 2>/dev/null || true
sleep 1

# Sync from chromium-kiosk branch (not main which has old ELF files)
log "Syncing from chromium-kiosk branch..."
if [ -d "$SOURCE_DIR/.git" ]; then
    cd "$SOURCE_DIR"
    timeout 15s git fetch origin chromium-kiosk >/dev/null 2>&1 || true
    if git rev-parse --verify origin/chromium-kiosk >/dev/null 2>&1; then
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/chromium-kiosk)
        if [ "$LOCAL" != "$REMOTE" ]; then
            log "Git: new commits on chromium-kiosk, updating..."
            git reset --hard origin/chromium-kiosk >/dev/null 2>&1
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/ >/dev/null 2>&1
            fi
            log "Git: synced to runtime folder"
        fi
    fi
fi

log "=== Kill-to-menu complete (xinitrc will restart) ==="

# Exit - the .xinitrc loop will restart Chromium automatically
