#!/bin/bash
LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
# Look for source at ../CreationStationArcade (strip -run suffix if present)
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR%-run}"}"

if [ -d "$SOURCE_DIR/.git" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Syncing from $SOURCE_DIR to $RUN_DIR" >> "$LOG_FILE"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --no-perms --no-owner --no-group --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: rsync not found; falling back to cp (no delete)" >> "$LOG_FILE"
        cp -a "$SOURCE_DIR"/. "$RUN_DIR"/ >> "$LOG_FILE" 2>&1
    fi

    chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/simpleLaunch.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
    find "$RUN_DIR" -type f -name "*.elf" -exec chmod +x {} \; 2>/dev/null || true
    chmod +x "$RUN_DIR/server.js" 2>/dev/null || true

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sync complete. Continuing without restart." >> "$LOG_FILE"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: Source repo not found at $SOURCE_DIR; starting without sync" >> "$LOG_FILE"
fi

# Check for /sd/prj folder and sync games if it exists
if [ -d "/sd/prj" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Found /sd/prj folder, syncing games..." >> "$LOG_FILE"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --no-perms --no-owner --no-group --delete "$RUN_DIR/games"/ "/sd/prj"/ >> "$LOG_FILE" 2>&1
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: rsync not found; falling back to cp (no delete)" >> "$LOG_FILE"
        cp -a "$RUN_DIR/games"/. "/sd/prj"/ >> "$LOG_FILE" 2>&1
    fi
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Games sync complete." >> "$LOG_FILE"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] no prj folder found, not using custom menu launcher" >> "$LOG_FILE"
fi

# Pull from git after we rsync to avoid race conditions and make this nice and fast to boot (when no wifi)
if [ -x "$RUN_DIR/pullFromGit.sh" ]; then
    "$RUN_DIR/pullFromGit.sh" &
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: pullFromGit.sh missing or not executable" >> "$LOG_FILE"
fi

# Start background monitor if not running
if ! pgrep -f "monitor_kill.py" > /dev/null; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting monitor_kill.py..." >> $LOG_FILE
    python3 "$RUN_DIR/monitor_kill.py" >> $LOG_FILE 2>&1 &
fi

# ── Kiosk launch ──────────────────────────────────────────────────────────
# Kill any leftover server or browser from a previous session
pkill -f "node.*server.js" 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 0.5

# Start local HTTP server
if command -v node >/dev/null 2>&1; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting HTTP server on port 3000" >> $LOG_FILE
    node "$RUN_DIR/server.js" >> $LOG_FILE 2>&1 &
    SERVER_PID=$!
    sleep 1.5
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: node not found. Install Node.js." >> $LOG_FILE
    exit 1
fi

# Launch Chromium in kiosk mode
CHROMIUM_BIN=""
for bin in chromium-browser chromium google-chrome; do
    if command -v $bin >/dev/null 2>&1; then
        CHROMIUM_BIN=$bin
        break
    fi
done

if [ -z "$CHROMIUM_BIN" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: chromium not found." >> $LOG_FILE
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Chromium kiosk" >> $LOG_FILE
"$CHROMIUM_BIN" \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --no-default-browser-check \
    --disable-pinch \
    --disable-gpu \
    --disable-software-rasterizer \
    --no-sandbox \
    http://localhost:3000 >> $LOG_FILE 2>&1

CHROMIUM_EXIT=$?
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chromium exited with status $CHROMIUM_EXIT" >> $LOG_FILE

# Clean up server on exit
kill $SERVER_PID 2>/dev/null || true