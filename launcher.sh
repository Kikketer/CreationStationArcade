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

# Determine the active game. SINGLE_GAME_NAME can name a directory in games/.
GAME_NAME="${SINGLE_GAME_NAME:-}"
if [ -z "$GAME_NAME" ]; then
    while IFS= read -r -d '' d; do
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            GAME_NAME="$(basename "$d")"
            break
        fi
    done < <(find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

GAME_DIR="$GAMES_DIR/$GAME_NAME"
if [ -z "$GAME_NAME" ] || [ ! -x "$GAME_DIR/Game" ] || [ ! -f "$GAME_DIR/libpxt.so" ]; then
    _log "ERROR: no native game found in $GAMES_DIR/<Name>/Game + libpxt.so"
    _log "Extract a game from make-web /desktop into $GAMES_DIR/<Name>/ and re-run the installer."
    sleep 5
    exit 1
fi

export SINGLE_GAME_NAME="$GAME_NAME"
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export LD_LIBRARY_PATH="$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

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

# Main loop: keep the native game running.
MAX_RETRIES="${ARCADE_MAX_RETRIES:-5}"
RETRY=0
while [ "$RETRY" -lt "$MAX_RETRIES" ]; do
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
