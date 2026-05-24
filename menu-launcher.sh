#!/bin/bash
# menu-launcher.sh - Launches menu Chromium (game Chromium spawned by server.js)
# This is the NEW dual-Chromium architecture where server spawns games directly

LOG_FILE="/home/pi/arcade.log"
PID_FILE="/tmp/arcade-server.pid"
MENU_CHROMIUM_PID_FILE="/tmp/arcade-menu-chromium.pid"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-${RUN_DIR%-run}}"

# Find chromium
CHROMIUM_BIN=$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)
if [ -z "$CHROMIUM_BIN" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Chromium not found" >> "$LOG_FILE"
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Menu Launcher Starting (Dual-Chromium Mode) ==="
log "Menu Chromium will be launched here. Game Chromium spawned by server.js"

# Kill any existing processes
kill $(cat $PID_FILE 2>/dev/null) 2>/dev/null || true
kill $(cat $MENU_CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
sleep 1

# Sync from source if available (catches background git updates)
if [ -d "$SOURCE_DIR/.git" ]; then
    log "Syncing from $SOURCE_DIR to $RUN_DIR"
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    log "Sync complete"
fi

# Start Node server
log "Starting Node server..."
cd "$RUN_DIR"
node server.js >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"

# Wait for server
log "Waiting for server..."
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        log "Server ready (server.js will spawn game Chromium when needed)"
        break
    fi
    sleep 1
done

# Common Chromium flags
CHROMIUM_FLAGS=(
    --user-data-dir=/tmp/chromium-arcade-menu
    --noerrdialogs
    --disable-infobars
    --no-first-run
    --disable-session-crashed-bubble
    --no-default-browser-check
    --disable-pinch
    --disable-extensions
    --disable-background-networking
    --disable-sync
    --disable-default-apps
    --disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy
    --ignore-gpu-blocklist
    --enable-gpu-rasterization
    --use-gl=egl
    --remote-debugging-port=9222
)

# Launch MENU Chromium (always running, kiosk mode, bottom layer)
log "Launching MENU Chromium (kiosk, always-on)..."
"$CHROMIUM_BIN" \
    --user-data-dir=/tmp/chromium-arcade-menu \
    --kiosk \
    --window-position=0,0 \
    --window-size=1920,1080 \
    --start-fullscreen \
    "${CHROMIUM_FLAGS[@]}" \
    http://localhost:3000/ >> "$LOG_FILE" 2>&1 &

MENU_PID=$!
echo $MENU_PID > "$MENU_CHROMIUM_PID_FILE"
log "Menu Chromium started (PID: $MENU_PID)"

# Wait for menu window to appear
sleep 3

# Focus the menu window
if command -v xdotool >/dev/null 2>&1; then
    for winclass in "chromium" "Chromium"; do
        WIN_ID=$(xdotool search --onlyvisible --class "$winclass" 2>/dev/null | head -1)
        if [ -n "$WIN_ID" ]; then
            xdotool windowfocus "$WIN_ID" 2>/dev/null || true
            xdotool windowactivate "$WIN_ID" 2>/dev/null || true
            log "Menu window focused"
            break
        fi
    done
fi

# Monitor loop - just keep menu running, server handles game spawning
while true; do
    # Check if menu died (restart if so)
    if ! kill -0 "$MENU_PID" 2>/dev/null; then
        log "WARNING: Menu Chromium died, restarting..."
        "$CHROMIUM_BIN" \
            --user-data-dir=/tmp/chromium-arcade-menu \
            --kiosk \
            --window-position=0,0 \
            --window-size=1920,1080 \
            --start-fullscreen \
            "${CHROMIUM_FLAGS[@]}" \
            http://localhost:3000/ >> "$LOG_FILE" 2>&1 &
        MENU_PID=$!
        echo $MENU_PID > "$MENU_CHROMIUM_PID_FILE"
        sleep 3
    fi
    
    sleep 2
done

log "=== Menu Launcher exited ==="
kill $SERVER_PID 2>/dev/null || true
rm -f "$PID_FILE" "$MENU_CHROMIUM_PID_FILE"
