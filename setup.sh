#!/bin/bash
# setup.sh — syncs from git repo to runtime folder
# Usage: Run from within the cloned repo (e.g., /home/pi/CreationStationArcade)
# Runtime folder will be ../CreationStationArcade-run

set -e

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${SOURCE_DIR}-run"

if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "ERROR: $SOURCE_DIR is not a git repo (missing .git)." >&2
    echo "This script must be run from the cloned repository." >&2
    exit 2
fi

LOG_FILE="/home/pi/arcade.log"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Setup: source=$SOURCE_DIR run=$RUN_DIR" >> "$LOG_FILE"

echo "Source: $SOURCE_DIR"
echo "Run:    $RUN_DIR"

mkdir -p "$RUN_DIR"

if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/
else
    cp -a "$SOURCE_DIR"/. "$RUN_DIR"/
fi

chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/simpleLaunch.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/pullFromGit.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/install/hdmi-audio-fix.sh" 2>/dev/null || true

echo "Done. Point login shell to: $RUN_DIR/launcher.sh"
