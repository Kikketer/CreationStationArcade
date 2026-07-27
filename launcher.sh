#!/bin/bash
# launcher.sh — single native MakeCode Arcade kiosk
# Run from the checkout directory (no separate runtime/source folders).

set -o pipefail

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"

_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

_log "Launcher starting (RUN_DIR=$RUN_DIR)"

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
