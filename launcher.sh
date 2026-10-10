#!/bin/bash
# launcher.sh — single native MakeCode Arcade kiosk
# Run from the checkout directory. Each game lives in games/<Name>/ with Game + libpxt.so.

set -o pipefail

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
export ARCADE_LOG="$LOG_FILE"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
GAMES_DIR="$RUN_DIR/games"

_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

_log "Launcher starting (RUN_DIR=$RUN_DIR)"

# Determine the active game. Priority: $RUN_DIR/.active-game (written by the
# USB updater for live switches), then SINGLE_GAME_NAME, then ControllerTest
# (the "does this thing work" sanity game), then the first valid directory
# in games/. Re-resolved each loop so a USB swap takes effect on the next
# launch without a reboot.
ACTIVE_FILE="$RUN_DIR/.active-game"

resolve_game() {
    local name=""
    if [ -f "$ACTIVE_FILE" ]; then
        name="$(head -n1 "$ACTIVE_FILE" | tr -cd 'A-Za-z0-9._-')"
    fi
    [ -n "$name" ] || name="${SINGLE_GAME_NAME:-}"
    if [ -z "$name" ] || [ ! -x "$GAMES_DIR/$name/Game" ] || [ ! -f "$GAMES_DIR/$name/libpxt.so" ]; then
        name="ControllerTest"
    fi
    if [ ! -x "$GAMES_DIR/$name/Game" ] || [ ! -f "$GAMES_DIR/$name/libpxt.so" ]; then
        name=""
        while IFS= read -r -d '' d; do
            if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
                name="$(basename "$d")"
                break
            fi
        done < <(find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    fi
    echo "$name"
}

GAME_NAME="$(resolve_game)"
GAME_DIR="$GAMES_DIR/$GAME_NAME"
if [ -z "$GAME_NAME" ] || [ ! -x "$GAME_DIR/Game" ] || [ ! -f "$GAME_DIR/libpxt.so" ]; then
    _log "ERROR: no native game found in $GAMES_DIR/<Name>/Game + libpxt.so"
    _log "Extract a game from the PNG to Desktop compiler into $GAMES_DIR/<Name>/ and re-run the installer."
    sleep 5
    exit 1
fi

export SINGLE_GAME_NAME="$GAME_NAME"
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa

# The bundled SDL renderers on ARM KMSDRM boards (vc4/lima/panfrost) work
# best with the OpenGL ES 2.0 driver.  Allow users to override if needed.
if [ -z "${SDL_RENDER_DRIVER:-}" ] && [ "$(uname -m)" = "aarch64" ]; then
    export SDL_RENDER_DRIVER=opengles2
fi

_log "Active game: $GAME_NAME"
_log "SDL_VIDEODRIVER=$SDL_VIDEODRIVER SDL_AUDIODRIVER=$SDL_AUDIODRIVER SDL_RENDER_DRIVER=${SDL_RENDER_DRIVER:-<default>}"

# GPIO reset helper: cabinet button on a ground-adjacent pin -> uinput 'r' key.
# Use the RPi.GPIO helper on Pi, the gpiod helper on boards like La Frite,
# or skip it entirely if neither GPIO library is installed.
if python3 -c "import RPi.GPIO" >/dev/null 2>&1; then
    GPIO_RESET_HELPER="$RUN_DIR/gpio-reset-keyboard.py"
elif python3 -c "import gpiod" >/dev/null 2>&1; then
    GPIO_RESET_HELPER="$RUN_DIR/gpio-reset-keyboard-gpiod.py"
else
    GPIO_RESET_HELPER=""
fi

if [ -n "$GPIO_RESET_HELPER" ]; then
    GPIO_RESET_ARGS=()
    if [ -n "${GPIO_RESET_PIN:-}" ]; then
        GPIO_RESET_ARGS+=(--pin "$GPIO_RESET_PIN")
    fi
    if [ "${GPIO_RESET_ACTIVE_HIGH:-0}" != "1" ]; then
        GPIO_RESET_ARGS+=(--active-low)
    fi
    pkill -f "gpio-reset-keyboard" 2>/dev/null || true
    python3 "$GPIO_RESET_HELPER" "${GPIO_RESET_ARGS[@]}" &
    RESET_PID=$!
    trap 'kill "$RESET_PID" 2>/dev/null || true' EXIT
    _log "GPIO reset helper started ($GPIO_RESET_HELPER pin=${GPIO_RESET_PIN:-<default>} args=${GPIO_RESET_ARGS[*]})"
else
    _log "GPIO reset helper skipped (no GPIO library installed)"
fi

# Main loop: keep the native game running. The game name is re-resolved
# every iteration so a USB install can switch the active game by updating
# .active-game and killing the running Game — no reboot needed.
MAX_RETRIES="${ARCADE_MAX_RETRIES:-5}"
RETRY=0
LAST_GAME=""
while [ "$RETRY" -lt "$MAX_RETRIES" ]; do
    GAME_NAME="$(resolve_game)"
    GAME_DIR="$GAMES_DIR/$GAME_NAME"
    if [ "$GAME_NAME" != "$LAST_GAME" ]; then
        RETRY=0
        LAST_GAME="$GAME_NAME"
    fi
    if [ -z "$GAME_NAME" ] || [ ! -x "$GAME_DIR/Game" ] || [ ! -f "$GAME_DIR/libpxt.so" ]; then
        _log "ERROR: no runnable game found; retrying in 5s"
        sleep 5
        continue
    fi
    # Keep .active-game in sync with what actually resolved, so a deleted
    # game's stale name doesn't linger (e.g. fail-over to ControllerTest).
    if [ "$(head -n1 "$ACTIVE_FILE" 2>/dev/null)" != "$GAME_NAME" ]; then
        echo "$GAME_NAME" > "$ACTIVE_FILE"
    fi
    export SINGLE_GAME_NAME="$GAME_NAME"
    export LD_LIBRARY_PATH="$GAME_DIR"
    _log "Launching $GAME_NAME (native Game)"
    "$RUN_DIR/single-native-launch.sh" "$GAME_DIR" >> "$LOG_FILE" 2>&1
    STATUS=$?
    RETRY=$((RETRY + 1))
    if [ "$RETRY" -lt "$MAX_RETRIES" ]; then
        _log "single-native-launch.sh exited with status $STATUS; restarting in 2s (attempt $RETRY/$MAX_RETRIES)"
        sleep 2
    fi
done
_log "ERROR: $GAME_NAME failed $MAX_RETRIES times; giving up"
exit 1
