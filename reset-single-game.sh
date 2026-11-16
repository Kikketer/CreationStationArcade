#!/bin/bash
# reset-single-game.sh - GPIO reset button handler for single-game kiosk mode
# Restarts the game by killing and relaunching Chromium.
# Before restarting it checks the floppy drive: a disk holding a new game is
# installed like a cartridge, and that game launches instead of the old one.

LOG_FILE="/home/pi/arcade.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# If already in -run folder, use it directly, otherwise append -run
if [[ "$SCRIPT_DIR" == *"-run" ]]; then
    RUN_DIR="$SCRIPT_DIR"
else
    RUN_DIR="${SCRIPT_DIR}-run"
fi
SOURCE_DIR="${CSA_SOURCE_DIR:-${RUN_DIR%-run}}"

# Disk-installed games live outside the checkout: this -run folder gets
# rsync --delete'd below and on every boot.
GAMES_DIR="${ARCADE_GAMES_DIR:-$HOME/arcade-games}"
ACTIVE_FILE="$GAMES_DIR/.active-game"
DISK_LOADER="${ARCADE_DISK_LOADER:-/usr/local/sbin/arcade-disk-load.sh}"
LOADING_PID_FILE="/tmp/arcade-loading-chromium.pid"

# A game installed from a disk wins over the compiled-in SINGLE_GAME_NAME —
# the disk is the cartridge and it stays "inserted" across reboots.
resolve_game() {
    local name=""
    [ -f "$ACTIVE_FILE" ] && name="$(head -n1 "$ACTIVE_FILE" | tr -cd 'A-Za-z0-9._-')"
    echo "${name:-${SINGLE_GAME_NAME:-AndyPaddleTheRiver}}"
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

launch_chromium() {
    "$CHROMIUM_BIN" \
        --user-data-dir=/tmp/chromium-arcade \
        --kiosk \
        --window-position=0,0 \
        --window-size=1920,1080 \
        --start-fullscreen \
        --noerrdialogs \
        --disable-infobars \
        --no-first-run \
        --disable-session-crashed-bubble \
        --disable-features=TranslateUI,Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies,InfiniteSessionRestore \
        --no-default-browser-check \
        --disable-pinch \
        --disable-extensions \
        --disable-background-networking \
        --disable-sync \
        --disable-default-apps \
        --disable-component-extensions-with-background-pages \
        --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy \
        --ignore-gpu-blocklist \
        --enable-gpu-rasterization \
        --force-gpu-rasterization \
        --enable-zero-copy \
        --enable-hardware-overlays \
        --use-gl=egl \
        --remote-debugging-port=9222 \
        "$1" >> $LOG_FILE 2>&1 &
}

log "=== Single-game reset triggered ==="

# Check the floppy drive for a new cartridge first. USB floppies don't
# announce disk insertion, so reset is the only time the disk gets read.
DISK_LOAD=0
if sudo -n "$DISK_LOADER" --check >/dev/null 2>&1; then
    DISK_LOAD=1
    log "New game found on disk; will load it after stopping the current game"
fi

# Kill existing Chromium
log "Killing Chromium for game restart..."
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
kill $(cat /tmp/arcade-chromium.pid 2>/dev/null) 2>/dev/null || true
rm -f /tmp/arcade-chromium.pid

# Restart GPIO gamepad service to ensure controllers are responsive
log "Restarting GPIO gamepad service..."
pkill -f "gpio-gamepad.py" 2>/dev/null || true
sleep 1
if [ -f "$RUN_DIR/gpio-gamepad.py" ]; then
    python3 "$RUN_DIR/gpio-gamepad.py" >> "$LOG_FILE" 2>&1 &
    log "GPIO gamepad service restarted"
fi

sleep 1

log "=== Reset: syncing code ==="

if [ -d "$SOURCE_DIR/.git" ]; then
    # Git pull in background (don't block restart, tolerates no network)
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

# Find chromium
CHROMIUM_BIN=$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)

if [ -z "$CHROMIUM_BIN" ]; then
    log "ERROR: Chromium not found"
    exit 1
fi

# Reading a floppy takes a while; show READING DISK while the game installs.
if [ "$DISK_LOAD" = "1" ]; then
    launch_chromium "http://localhost:3000/loading.html"
    echo $! > "$LOADING_PID_FILE"
    sudo -n "$DISK_LOADER" >> "$LOG_FILE" 2>&1 || true
    kill $(cat "$LOADING_PID_FILE" 2>/dev/null) 2>/dev/null || true
    pkill -f "chromium.*localhost:3000/loading" 2>/dev/null || true
    rm -f "$LOADING_PID_FILE"
fi

GAME_NAME="$(resolve_game)"

# Restart Chromium with the active game (the disk's game if one was loaded)
log "Restarting Chromium with game: $GAME_NAME"
launch_chromium "http://localhost:3000/play?game=$GAME_NAME"

CHROMIUM_PID=$!
echo $CHROMIUM_PID > /tmp/arcade-chromium.pid

log "Chromium restarted (PID: $CHROMIUM_PID)"

# Focus the window after restart
sleep 4
if command -v xdotool >/dev/null 2>&1; then
    for winclass in "chromium" "Chromium" "chromium-browser"; do
        WIN_ID=$(xdotool search --onlyvisible --class "$winclass" 2>/dev/null | head -1)
        if [ -n "$WIN_ID" ]; then
            xdotool windowfocus "$WIN_ID" 2>/dev/null || true
            xdotool windowactivate "$WIN_ID" 2>/dev/null || true
            sleep 0.5
            xdotool click --window "$WIN_ID" 1 2>/dev/null || true
            for i in 1 2 3; do
                xdotool key --clearmodifiers Tab 2>/dev/null || true
                sleep 0.2
            done
            log "Window focused after restart"
            break
        fi
    done
fi

log "=== Single-game reset complete ==="
