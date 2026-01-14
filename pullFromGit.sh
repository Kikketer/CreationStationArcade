#!/bin/bash

LOG_FILE="/home/pi/arcade.log"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR}-src"}"

if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: source repo not found at $SOURCE_DIR" >> "$LOG_FILE"
    exit 0
fi

cd "$SOURCE_DIR" || exit 0

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: fetching origin" >> "$LOG_FILE"
if command -v timeout >/dev/null 2>&1; then
    timeout 15s git fetch origin >> "$LOG_FILE" 2>&1 || true
else
    git fetch origin >> "$LOG_FILE" 2>&1 || true
fi

if git rev-parse --verify origin/main >/dev/null 2>&1; then
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Background update: resetting to origin/main" >> "$LOG_FILE"
        git reset --hard origin/main >> "$LOG_FILE" 2>&1 || true
    fi
fi
