#!/bin/bash

set -e

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SOURCE_DIR" != *-src ]]; then
    echo "ERROR: setup.sh must be run from the source repo folder named '*-src'." >&2
    echo "Example:" >&2
    echo "  /home/pi/CreationStationArcade-src  (source repo)" >&2
    echo "  /home/pi/CreationStationArcade      (runtime folder)" >&2
    exit 2
fi

if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "ERROR: $SOURCE_DIR is not a git repo (missing .git)." >&2
    exit 2
fi

RUN_DIR="${SOURCE_DIR%-src}"

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

echo "Done. If you use the two-folder flow, point login shell to: $RUN_DIR/launcher.sh"
