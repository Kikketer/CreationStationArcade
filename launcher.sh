#!/bin/bash
# launcher.sh — single native MakeCode Arcade kiosk
# Run from the checkout directory. Each game is an executable file in games/<Name>;
# libpxt.so is shared in the games/ directory.

set -o pipefail

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
GAMES_DIR="$RUN_DIR/games"

_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

_log "Launcher starting (RUN_DIR=$RUN_DIR)"

if [ ! -f "$GAMES_DIR/libpxt.so" ]; then
    _log "ERROR: shared library not found: $GAMES_DIR/libpxt.so"
    _log "Place the architecture-matching libpxt.so in $GAMES_DIR/ and add game binaries."
    sleep 5
    exit 1
fi

# Determine the active game. SINGLE_GAME_NAME can name a file in games/ (not libpxt.so).
GAME_NAME="${SINGLE_GAME_NAME:-}"
if [ -z "$GAME_NAME" ]; then
    while IFS= read -r -d '' f; do
        name="$(basename "$f")"
        if [ "$name" = "libpxt.so" ]; then
            continue
        fi
        if [ -x "$f" ] && [ ! -d "$f" ]; then
            GAME_NAME="$name"
            break
        fi
    done < <(find "$GAMES_DIR" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
fi

GAME_FILE="$GAMES_DIR/$GAME_NAME"
if [ -z "$GAME_NAME" ] || [ ! -x "$GAME_FILE" ] || [ -d "$GAME_FILE" ]; then
    _log "ERROR: no native game executable found in $GAMES_DIR/"
    _log "Add a game binary from make-web /desktop and re-run the installer."
    sleep 5
    exit 1
fi

export SINGLE_GAME_NAME="$GAME_NAME"
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export LD_LIBRARY_PATH="$GAMES_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

_log "Active game: $GAME_NAME"
_log "SDL_VIDEODRIVER=$SDL_VIDEODRIVER SDL_AUDIODRIVER=$SDL_AUDIODRIVER"

# Main loop: keep the native game running.
while true; do
    _log "Launching $GAME_NAME (native Game)"
    "$RUN_DIR/single-native-launch.sh" "$GAME_FILE" >> "$LOG_FILE" 2>&1
    STATUS=$?
    _log "single-native-launch.sh exited with status $STATUS; restarting in 2s"
    sleep 2
done
