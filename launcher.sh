#!/bin/bash
LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR}-src"}"

## CHANGE THIS to set the game to play!
ACTIVE_GAME="Super-Star-Story"

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
    chmod +x "$RUN_DIR/launchGame.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
    find "$RUN_DIR" -type f -name "*.elf" -exec chmod +x {} \; 2>/dev/null || true

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sync complete. Continuing without restart." >> "$LOG_FILE"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: Source repo not found at $SOURCE_DIR; starting without sync" >> "$LOG_FILE"
fi

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

RUNNER="$RUN_DIR/simpleLaunch.sh"
if [ ! -x "$RUNNER" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $RUNNER is missing or not executable" >> $LOG_FILE
    exit 1
fi

while true; do
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Menu" >> $LOG_FILE
    "$RUNNER" "$RUN_DIR/MadeArcadeMenu.elf" >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Menu exited with status $?" >> $LOG_FILE

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Game" >> $LOG_FILE
    "$RUNNER" "$RUN_DIR/games/$ACTIVE_GAME.elf" >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Game exited with status $?" >> $LOG_FILE
done