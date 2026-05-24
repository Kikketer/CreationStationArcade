#!/bin/bash
# dual-chromium-launcher.sh - Two Chromium instances: menu (bottom) + game (top)
# When game Chromium is killed, menu is instantly visible underneath

LOG_FILE="/home/pi/arcade.log"
PID_FILE="/tmp/arcade-server.pid"
MENU_CHROMIUM_PID_FILE="/tmp/arcade-menu-chromium.pid"
GAME_CHROMIUM_PID_FILE="/tmp/arcade-game-chromium.pid"

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

log "=== Dual Chromium Launcher Starting ==="

# Kill any existing processes
kill $(cat $PID_FILE 2>/dev/null) 2>/dev/null || true
kill $(cat $MENU_CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
kill $(cat $GAME_CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
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
        log "Server ready"
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
# Use a different user-data-dir so it doesn't conflict with game instance
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
            break
        fi
    done
fi

# Watch for game launch requests via API endpoint
# The menu will call /api/launch-game?name=GameName which triggers game Chromium
log "Starting game launch monitor..."
while true; do
    # Check if game launch was requested (file-based IPC)
    if [ -f /tmp/arcade-launch-game ]; then
        GAME_NAME=$(cat /tmp/arcade-launch-game)
        rm -f /tmp/arcade-launch-game
        
        # Kill any existing game Chromium
        kill $(cat "$GAME_CHROMIUM_PID_FILE" 2>/dev/null) 2>/dev/null || true
        pkill -f "chromium.*localhost:3000/play" 2>/dev/null || true
        sleep 0.5
        
        # Launch GAME Chromium (on top of menu)
        # This is NOT kiosk mode - it's a regular window that covers the menu
        log "Launching GAME Chromium for: $GAME_NAME"
        "$CHROMIUM_BIN" \
            --user-data-dir=/tmp/chromium-arcade-game \
            --window-position=0,0 \
            --window-size=1920,1080 \
            --start-fullscreen \
            --noerrdialogs \
            --disable-infobars \
            --no-first-run \
            --disable-session-crashed-bubble \
            --no-default-browser-check \
            --disable-pinch \
            --disable-extensions \
            --disable-background-networking \
            --disable-sync \
            --disable-default-apps \
            --disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies \
            --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy \
            --ignore-gpu-blocklist \
            --enable-gpu-rasterization \
            --use-gl=egl \
            "http://localhost:3000/play?game=$GAME_NAME" >> "$LOG_FILE" 2>&1 &
        
        GAME_PID=$!
        echo $GAME_PID > "$GAME_CHROMIUM_PID_FILE"
        log "Game Chromium started (PID: $GAME_PID) for $GAME_NAME"
        
        # Focus the game window (it should be on top)
        sleep 2
        if command -v xdotool >/dev/null 2>&1; then
            # Find the newest Chromium window
            WIN_IDS=$(xdotool search --class "chromium" 2>/dev/null)
            for WIN_ID in $WIN_IDS; do
                xdotool windowactivate "$WIN_ID" 2>/dev/null || true
            done
        fi
    fi
    
    # Check if menu died (shouldn't happen, but restart if it does)
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
    
    sleep 0.5
done

log "=== Launcher exited ==="
kill $SERVER_PID 2>/dev/null || true
rm -f "$PID_FILE" "$MENU_CHROMIUM_PID_FILE" "$GAME_CHROMIUM_PID_FILE"
