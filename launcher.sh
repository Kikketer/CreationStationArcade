#!/bin/bash
# launcher.sh — multi native MakeCode Arcade kiosk
# Run from the checkout directory. Each game lives in games/<Name>/ with
# Game + libpxt.so. The menu is just another native game (games/Menu/ by
# default) that picks which game to launch next.
#
# Menu -> game contract (the "control" hook):
#   The menu writes the chosen games/<Name> directory name, one line, to
#   $ARCADE_LAUNCH_FILE (default /tmp/creationstation_launch_request) and
#   then exits. This script reads that file, launches the requested game,
#   and when that game exits it comes back here and relaunches the menu.
#   If the file is absent or names a game that isn't installed, the menu
#   is relaunched instead.

set -o pipefail

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
export ARCADE_LOG="$LOG_FILE"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR"
GAMES_DIR="$RUN_DIR/games"

# These two are the hooks a menu-capable native Game binary needs from the
# compiler/runtime: where to find the sibling games, and where to write the
# launch request before exiting.
export ARCADE_GAMES_DIR="$GAMES_DIR"
MENU_NAME="${ARCADE_MENU_NAME:-Menu}"
export ARCADE_LAUNCH_FILE="${ARCADE_LAUNCH_FILE:-/tmp/creationstation_launch_request}"
REQUEST_FILE="$ARCADE_LAUNCH_FILE"

_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

_log "Launcher starting (RUN_DIR=$RUN_DIR, menu=$MENU_NAME)"

is_game() {
    [ -n "$1" ] && [ -x "$GAMES_DIR/$1/Game" ] && [ -f "$GAMES_DIR/$1/libpxt.so" ]
}

# Pick what to run when there is no pending launch request: the menu game,
# then ControllerTest (the "does this thing work" sanity game), then the
# first valid directory in games/.
resolve_default() {
    local name=""
    if is_game "$MENU_NAME"; then
        name="$MENU_NAME"
    elif is_game "ControllerTest"; then
        name="ControllerTest"
    else
        while IFS= read -r -d '' d; do
            if is_game "$(basename "$d")"; then
                name="$(basename "$d")"
                break
            fi
        done < <(find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    fi
    echo "$name"
}

# A launch request is a single line naming a games/<Name> directory.
read_request() {
    local name=""
    if [ -s "$REQUEST_FILE" ]; then
        name="$(head -n1 "$REQUEST_FILE" | tr -cd 'A-Za-z0-9._-')"
        rm -f "$REQUEST_FILE"
    fi
    if [ -n "$name" ] && ! is_game "$name"; then
        _log "Launch request '$name' is not an installed game; ignoring"
        name=""
    fi
    echo "$name"
}

FIRST_TARGET="$(resolve_default)"
if [ -z "$FIRST_TARGET" ] && [ ! -s "$REQUEST_FILE" ]; then
    _log "ERROR: no native game found in $GAMES_DIR/<Name>/Game + libpxt.so"
    _log "Extract games from the PNG to Desktop compiler into $GAMES_DIR/<Name>/ and re-run the installer."
    sleep 5
    exit 1
fi

export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa

# The bundled SDL renderers on ARM KMSDRM boards (vc4/lima/panfrost) work
# best with the OpenGL ES 2.0 driver.  Allow users to override if needed.
if [ -z "${SDL_RENDER_DRIVER:-}" ] && [ "$(uname -m)" = "aarch64" ]; then
    export SDL_RENDER_DRIVER=opengles2
fi

_log "SDL_VIDEODRIVER=$SDL_VIDEODRIVER SDL_AUDIODRIVER=$SDL_AUDIODRIVER SDL_RENDER_DRIVER=${SDL_RENDER_DRIVER:-<default>}"

# GPIO reset helper: cabinet button on a ground-adjacent pin -> uinput 'r' key.
# Use the RPi.GPIO helper on Pi, the gpiod helper on boards like La Frite,
# or skip it entirely if neither GPIO library is installed.
# When /etc/arcade.cfg maps BTN_EXIT, the Game owns the exit button itself —
# don't start the reset helper (it would fight the Game for the same line
# on single-button cabinets where reset == exit-to-menu).
ARCADE_CFG="${ARCADE_GPIO_CFG:-/etc/arcade.cfg}"
if grep -q '^BTN_EXIT=' "$ARCADE_CFG" 2>/dev/null; then
    GPIO_RESET_SKIP="BTN_EXIT configured"
    GPIO_RESET_HELPER=""
elif python3 -c "import RPi.GPIO" >/dev/null 2>&1; then
    GPIO_RESET_HELPER="$RUN_DIR/gpio-reset-keyboard.py"
elif python3 -c "import gpiod" >/dev/null 2>&1; then
    GPIO_RESET_HELPER="$RUN_DIR/gpio-reset-keyboard-gpiod.py"
else
    GPIO_RESET_HELPER=""
fi

if [ -n "$GPIO_RESET_HELPER" ]; then
    GPIO_RESET_ARGS=()
    if [ -n "${GPIO_RESET_CHIP:-}" ]; then
        GPIO_RESET_ARGS+=(--chip "$GPIO_RESET_CHIP")
    fi
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
    _log "GPIO reset helper skipped (${GPIO_RESET_SKIP:-no GPIO library installed})"
fi

# Main loop: menu -> requested game -> menu -> ...
# The launch request file is re-read every iteration, so the menu (or the
# USB installer) can point at a different game each time. A game that exits
# on its own (BTN_EXIT / control.exit) simply returns to the menu.
MAX_RETRIES="${ARCADE_MAX_RETRIES:-5}"
RETRY=0
LAST_TARGET=""
while true; do
    TARGET="$(read_request)"
    if [ -z "$TARGET" ]; then
        TARGET="$(resolve_default)"
    fi
    if [ "$TARGET" != "$LAST_TARGET" ]; then
        RETRY=0
        LAST_TARGET="$TARGET"
    fi
    if [ -z "$TARGET" ]; then
        _log "ERROR: no runnable game found; retrying in 5s"
        sleep 5
        continue
    fi
    export LD_LIBRARY_PATH="$GAMES_DIR/$TARGET"
    _log "Launching $TARGET (native Game)"
    "$RUN_DIR/launch-game.sh" "$GAMES_DIR/$TARGET" >> "$LOG_FILE" 2>&1
    STATUS=$?
    RETRY=$((RETRY + 1))
    if [ "$STATUS" != "0" ]; then
        if [ "$RETRY" -ge "$MAX_RETRIES" ] && [ "$TARGET" != "$MENU_NAME" ]; then
            _log "WARNING: $TARGET failed $MAX_RETRIES times in a row; falling back to the menu"
            RETRY=0
            LAST_TARGET=""
        else
            _log "$TARGET exited with status $STATUS (attempt $RETRY/$MAX_RETRIES)"
            sleep 2
        fi
    else
        _log "$TARGET exited cleanly; back to the menu"
    fi
done
