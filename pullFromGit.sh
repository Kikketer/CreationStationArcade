#!/bin/bash
# Pull from git and sync to runtime folder
# Can be called from source repo or runtime folder

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine source and run directories
if [ -d "$SCRIPT_DIR/.git" ]; then
    # Running from source repo
    SOURCE_DIR="$SCRIPT_DIR"
    RUN_DIR="${SOURCE_DIR}-run"
else
    # Running from runtime folder (assume it's named -run)
    RUN_DIR="$SCRIPT_DIR"
    SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR%-run}"}"
fi

if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: source repo not found at $SOURCE_DIR" >> "$LOG_FILE"
    exit 0
fi

cd "$SOURCE_DIR" || exit 0

# Detect current branch dynamically
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: fetching origin ($BRANCH)" >> "$LOG_FILE"
if command -v timeout >/dev/null 2>&1; then
    timeout 15s git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1 || true
else
    git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1 || true
fi

if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$BRANCH)" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: resetting to origin/$BRANCH" >> "$LOG_FILE"
        git reset --hard "origin/$BRANCH" >> "$LOG_FILE" 2>&1 || true
    fi
fi

# Always sync to runtime folder (ensures -run matches source even if no new commits)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: syncing to runtime folder" >> "$LOG_FILE"
mkdir -p "$RUN_DIR"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --no-group --no-owner --delete --exclude ".git" --exclude "arcade.log" --exclude ".lgd-*" "$SOURCE_DIR"/ "$RUN_DIR"/
else
    rm -rf "$RUN_DIR"
    cp -a "$SOURCE_DIR" "$RUN_DIR"
fi
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: sync complete" >> "$LOG_FILE"
