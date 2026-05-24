#!/bin/bash
# kill-to-menu.sh - GPIO reset button handler for Chromium kiosk mode
# Uses remote debugging protocol to force navigation to menu

LOG_FILE="/home/pi/arcade.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${SCRIPT_DIR}-run"
SOURCE_DIR="${CSA_SOURCE_DIR:-$SCRIPT_DIR}"
DEBUG_PORT=9222
MENU_URL="http://localhost:3000/"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Kill-to-menu triggered ==="

# ── Use Chromium remote debugging to force navigate to menu ───────────────────
log "Forcing Chromium navigation to menu via debugging protocol..."

# Wait a moment for debugging port to be available if Chromium just started
sleep 0.5

# Check if debugging port is accessible
if curl -s "http://localhost:$DEBUG_PORT/json/list" >/dev/null 2>&1; then
    # Get the first page ID
    PAGE_ID=$(curl -s "http://localhost:$DEBUG_PORT/json/list" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$PAGE_ID" ]; then
        log "Found page ID: $PAGE_ID, navigating to $MENU_URL"
        
        # Send navigate command via HTTP POST to the protocol endpoint
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"$MENU_URL\"}}" \
            "http://localhost:$DEBUG_PORT/json/$PAGE_ID" >/dev/null 2>&1
        
        log "Navigation command sent to Chromium"
    else
        log "WARNING: Could not find page ID, trying fallback method"
        # Fallback: open new tab with menu URL
        curl -s "http://localhost:$DEBUG_PORT/json/new?$MENU_URL" >/dev/null 2>&1 || true
    fi
else
    log "WARNING: Chromium debugging port not available (port $DEBUG_PORT)"
    # Fallback: try xdotool Escape key
    if command -v xdotool >/dev/null 2>&1; then
        for winclass in "chromium" "Chromium" "chromium-browser"; do
            WIN_ID=$(xdotool search --onlyvisible --class "$winclass" 2>/dev/null | head -1)
            if [ -n "$WIN_ID" ]; then
                log "Fallback: sending Escape to window $WIN_ID"
                xdotool key --window "$WIN_ID" Escape 2>/dev/null || true
                break
            fi
        done
    fi
fi

# ── Background git update (non-blocking) ────────────────────────────────────
log "Starting background git update..."
(
    if [ -d "$SOURCE_DIR/.git" ]; then
        cd "$SOURCE_DIR" || exit
        timeout 15s git fetch origin >/dev/null 2>&1 || true
        if git rev-parse --verify origin/main >/dev/null 2>&1; then
            if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
                log "Git: new commits found, updating..."
                git reset --hard origin/main >/dev/null 2>&1 || true
                
                # Sync to runtime folder
                if [ -d "$RUN_DIR" ]; then
                    if command -v rsync >/dev/null 2>&1; then
                        rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/
                    else
                        rm -rf "$RUN_DIR"
                        cp -a "$SOURCE_DIR" "$RUN_DIR"
                    fi
                    log "Git: synced to runtime folder"
                fi
            else
                log "Git: already up to date"
            fi
        fi
    fi
) &

log "=== Kill-to-menu complete ==="
