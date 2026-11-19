#!/bin/bash
# menu-launcher.sh - Launches the single kiosk Chromium window
# The menu page swaps games in/out via iframe — one window for everything

LOG_FILE="$HOME/arcade.log"
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

log "=== Menu Launcher Starting (Single-Window Mode) ==="
log "One kiosk Chromium serves menu + games (iframe swap)."


# Kill any existing processes
kill $(cat $PID_FILE 2>/dev/null) 2>/dev/null || true
kill $(cat $MENU_CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
sleep 1

# Pull latest from git and sync to runtime folder
if [ -d "$SOURCE_DIR/.git" ]; then
    log "Pulling latest from source repo..."
    cd "$SOURCE_DIR"
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    timeout 10s git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1 || true
    if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$BRANCH")
        if [ "$LOCAL" != "$REMOTE" ]; then
            log "Git: updating source to origin/$BRANCH"
            git reset --hard "origin/$BRANCH" >> "$LOG_FILE" 2>&1
        fi
    fi
    log "Syncing from $SOURCE_DIR to $RUN_DIR"
    rsync -a --no-group --no-owner --delete --exclude ".git" --exclude "arcade.log" --exclude ".lgd-*" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
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
    --disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies,InfiniteSessionRestore
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy
    --ignore-gpu-blocklist
    --enable-gpu-rasterization
    --use-gl=egl
    --hide-scrollbars
    --suppress-message-center-popups
    --remote-debugging-port=9222
)

# Size windows to the actual display — kiosk alone doesn't stretch the
# window on some X setups; give it the real resolution. A
# "display.resolution" override in config.jsonc wins over xrandr.
CFG_RES="$(python3 -c "
import json, re, sys
try:
    s = open(sys.argv[1]).read()
    s = re.sub(r'//[^\\n]*', '', s)
    s = re.sub(r'/\\*.*?\\*/', '', s, flags=re.S)
    print(json.loads(s).get('display', {}).get('resolution', ''))
except Exception:
    print('')
" "$HOME/arcade-games/config.jsonc" 2>/dev/null)"
RES="${CFG_RES:-$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}')}"
[ -n "$RES" ] || RES="1920x1080"
log "Display resolution: $RES"

# Launch the kiosk Chromium (only window ever opened)
log "Launching kiosk Chromium..."
"$CHROMIUM_BIN" \
    --user-data-dir=/tmp/chromium-arcade-menu \
    --kiosk \
    --window-size=$RES \
    --start-fullscreen \
    "${CHROMIUM_FLAGS[@]}" \
    http://localhost:3000/ >> "$LOG_FILE" 2>&1 &

MENU_PID=$!
echo $MENU_PID > "$MENU_CHROMIUM_PID_FILE"
log "Kiosk Chromium started (PID: $MENU_PID)"

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

# Monitor loop - keep the single kiosk window running
while true; do
    # Check if it died (restart if so)
    if ! kill -0 "$MENU_PID" 2>/dev/null; then
        log "WARNING: Kiosk Chromium died, restarting..."
        "$CHROMIUM_BIN" \
            --user-data-dir=/tmp/chromium-arcade-menu \
            --kiosk \
    --window-size=$RES \
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
