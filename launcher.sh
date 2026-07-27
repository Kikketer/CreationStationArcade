#!/bin/bash
# launcher.sh — single native MakeCode Arcade kiosk
# Runs from the runtime folder and syncs from the source repo before launching.

set -o pipefail

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${CSA_SOURCE_DIR:-"${RUN_DIR}-src"}"

_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

_log "Launcher starting (RUN_DIR=$RUN_DIR)"

# Sync from the source repo when it is present.
if [ -d "$SOURCE_DIR/.git" ]; then
    _log "Syncing from $SOURCE_DIR to $RUN_DIR"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --no-perms --no-owner --no-group --delete \
            --exclude ".git" --exclude "arcade.log" \
            "$SOURCE_DIR"/ "$RUN_DIR"/
    else
        _log "WARNING: rsync not found; copying without delete"
        cp -a "$SOURCE_DIR"/. "$RUN_DIR"/
    fi

    chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
    chmod +x "$RUN_DIR/single-native-launch.sh" 2>/dev/null || true
    find "$RUN_DIR/games" -maxdepth 2 -type f -name "Game" -exec chmod +x {} \; 2>/dev/null || true
    _log "Sync complete"
else
    _log "WARNING: Source repo not found at $SOURCE_DIR; starting without sync"
fi

# Determine the active game. SINGLE_GAME_NAME can come from the environment or default to the first valid game.
GAME_NAME="${SINGLE_GAME_NAME:-}"
if [ -z "$GAME_NAME" ]; then
    while IFS= read -r -d '' d; do
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            GAME_NAME="$(basename "$d")"
            break
        fi
    done < <(find "$RUN_DIR/games" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

if [ -z "$GAME_NAME" ]; then
    _log "ERROR: no native game found in $RUN_DIR/games/*/Game + libpxt.so"
    _log "Add a game from make-web /desktop and re-run the installer."
    sleep 5
    exit 1
fi

export SINGLE_GAME_NAME="$GAME_NAME"
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export LD_LIBRARY_PATH="$RUN_DIR/games/$GAME_NAME${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
GAME_DIR="$RUN_DIR/games/$GAME_NAME"

_log "Active game: $GAME_NAME"
_log "SDL_VIDEODRIVER=$SDL_VIDEODRIVER SDL_AUDIODRIVER=$SDL_AUDIODRIVER"

# Main loop: keep the native game running.
while true; do
    _log "Launching $GAME_NAME (native Game)"
    "$RUN_DIR/single-native-launch.sh" "$GAME_DIR" >> "$LOG_FILE" 2>&1
    STATUS=$?
    _log "single-native-launch.sh exited with status $STATUS; restarting in 2s"
    sleep 2
done
