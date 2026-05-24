#!/bin/bash
# launcher.sh - Chromium kiosk launcher for Creation Station Arcade
LOG_FILE="/home/pi/arcade.log"
PID_FILE="/tmp/arcade-server.pid"
CHROMIUM_PID_FILE="/tmp/arcade-chromium.pid"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR%-run}"}"

# Find chromium
CHROMIUM_BIN=$(which chromium 2>/dev/null || which chromium-browser 2>/dev/null || which google-chrome 2>/dev/null)

if [ -z "$CHROMIUM_BIN" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Chromium not found" >> $LOG_FILE
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Using Chromium: $CHROMIUM_BIN" >> $LOG_FILE

# Sync from source to runtime folder (source may have been updated in background)
if [ -d "$SOURCE_DIR/.git" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Syncing from $SOURCE_DIR to $RUN_DIR" >> "$LOG_FILE"
    # Check if source is on chromium-kiosk branch, update if needed (quick check, 10s timeout)
    cd "$SOURCE_DIR"
    timeout 10s git fetch origin chromium-kiosk >> "$LOG_FILE" 2>&1 || true
    if git rev-parse --verify origin/chromium-kiosk >/dev/null 2>&1; then
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/chromium-kiosk)
        if [ "$LOCAL" != "$REMOTE" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Git: updating source to origin/chromium-kiosk" >> "$LOG_FILE"
            git reset --hard origin/chromium-kiosk >> "$LOG_FILE" 2>&1
        fi
    fi
    # Always sync source to runtime folder (catches background updates or local edits)
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sync complete" >> "$LOG_FILE"
fi
# Kill any existing processes
kill $(cat $PID_FILE 2>/dev/null) 2>/dev/null || true
kill $(cat $CHROMIUM_PID_FILE 2>/dev/null) 2>/dev/null || true
pkill -f "chromium.*localhost:3000" 2>/dev/null || true
sleep 1

# Start Node server
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Node server..." >> $LOG_FILE
cd "$RUN_DIR"
node server.js >> $LOG_FILE 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > $PID_FILE

# Wait for server
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Waiting for server..." >> $LOG_FILE
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Server ready" >> $LOG_FILE
        break
    fi
    sleep 1
done

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Chromium kiosk" >> $LOG_FILE
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
    --disable-features=TranslateUI \
    --no-default-browser-check \
    --disable-pinch \
    --disable-extensions \
    --disable-background-networking \
    --disable-sync \
    --disable-default-apps \
    --disable-component-extensions-with-background-pages \
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy \
    --disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --force-gpu-rasterization \
    --enable-zero-copy \
    --enable-hardware-overlays \
    --use-gl=egl \
    --remote-debugging-port=9222 \
    http://localhost:3000 >> $LOG_FILE 2>&1 &

CHROMIUM_PID=$!
echo $CHROMIUM_PID > $CHROMIUM_PID_FILE

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chromium started (PID: $CHROMIUM_PID)" >> $LOG_FILE

# Wait for window to appear then focus it (fixes keyboard input issue)
sleep 4
if command -v xdotool >/dev/null 2>&1; then
    # Try multiple window class names Chromium might use
    for winclass in "chromium" "Chromium" "chromium-browser"; do
        WIN_ID=$(xdotool search --onlyvisible --class "$winclass" 2>/dev/null | head -1)
        if [ -n "$WIN_ID" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Found window $WIN_ID with class $winclass" >> $LOG_FILE
            xdotool windowfocus "$WIN_ID" 2>/dev/null || true
            xdotool windowactivate "$WIN_ID" 2>/dev/null || true
            sleep 0.5
            xdotool click --window "$WIN_ID" 1 2>/dev/null || true
            # Spam a few Tab presses to ensure focus (user tested: multiple tabs keep focus)
            for i in 1 2 3; do
                xdotool key --clearmodifiers Tab 2>/dev/null || true
                sleep 0.2
            done
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Window focused with triple-tab" >> $LOG_FILE
            break
        fi
    done
fi

wait $CHROMIUM_PID
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chromium exited" >> $LOG_FILE

# Cleanup
kill $SERVER_PID 2>/dev/null || true
rm -f $PID_FILE $CHROMIUM_PID_FILE