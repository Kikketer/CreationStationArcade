#!/bin/bash
# la-frite-native-arcade-setup.sh — one-shot installer for the La Frite single native arcade kiosk.
# Run from the checkout directory on the target machine (usually as root).
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "ERROR: This script requires bash." >&2
        exit 1
    fi
fi
set -e

REQUESTED_GAME=""
REQUESTED_USER=""
REQUESTED_RESET_PIN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --user=*) REQUESTED_USER="${1#*=}"; shift ;;
        --user) REQUESTED_USER="$2"; shift 2 ;;
        --game=*) REQUESTED_GAME="${1#*=}"; shift ;;
        --game) REQUESTED_GAME="$2"; shift 2 ;;
        --gpio-reset-pin=*) REQUESTED_RESET_PIN="${1#*=}"; shift ;;
        --gpio-reset-pin) REQUESTED_RESET_PIN="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--user=UserName] [--game=GameName] [--gpio-reset-pin=Pin]"
            echo "  --user             defaults to SUDO_USER, then the user running sudo, then 'arcade'."
            echo "  --game             selects the games/<Name>/Game + libpxt.so to boot."
            echo "  --gpio-reset-pin   gpiod line name or offset for the cabinet reset button (default 20)."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

GPIO_RESET_PIN="${REQUESTED_RESET_PIN:-20}"

if [ -n "$REQUESTED_USER" ]; then
    ARCADE_USER="$REQUESTED_USER"
elif [ -n "${SUDO_USER:-}" ]; then
    ARCADE_USER="$SUDO_USER"
else
    ARCADE_USER="$(logname 2>/dev/null || echo arcade)"
fi

if ! id -u "$ARCADE_USER" >/dev/null 2>&1; then
    echo "ERROR: user '$ARCADE_USER' does not exist. Create the user first or pass --user=." >&2
    exit 1
fi

ARCADE_USER_HOME="$(getent passwd "$ARCADE_USER" | cut -d: -f6)"
if [ -z "$ARCADE_USER_HOME" ]; then
    ARCADE_USER_HOME="/home/$ARCADE_USER"
    echo "WARNING: could not look up home directory for $ARCADE_USER; using $ARCADE_USER_HOME" >&2
fi

RUN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAMES_DIR="$RUN_DIR/games"
LOG_FILE="$ARCADE_USER_HOME/arcade.log"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true
chown "$ARCADE_USER:$ARCADE_USER" "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This installer must be run as root (try: sudo $0)" >&2
    exit 1
fi

log "=== la-frite-native-arcade setup ==="
log "Checkout directory: $RUN_DIR"
log "User:               $ARCADE_USER"
log "Log file:           $LOG_FILE"
log "Reset pin:          $GPIO_RESET_PIN"

# 1. System packages
log "Installing system packages..."
apt-get update
apt-get install -y git libsdl2-2.0-0 libdrm2 libgbm1 libudev1 libasound2 libgl1-mesa-dri libegl1 libgles2 python3-libgpiod

# 1a. Architecture check
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    arm64|aarch64|x86_64|amd64)
        log "Architecture: $ARCH"
        ;;
    armhf)
        log "WARNING: 32-bit armhf ($ARCH) detected. The bundled Game binaries are 64-bit; install a 64-bit OS before continuing."
        ;;
    *)
        log "WARNING: architecture '$ARCH' may not be supported by the bundled Game binaries."
        ;;
esac

# 1b. Board-specific GPU sanity for La Frite
is_raspberry_pi() {
    grep -qE "Raspberry Pi|BCM2835|BCM2836|BCM2837|BCM2711|BCM2712" /proc/cpuinfo 2>/dev/null || \
    grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null
}

is_la_frite() {
    grep -qiE "la.?frite|aml.?s805x|amlogic" /proc/device-tree/model 2>/dev/null || \
    grep -qiE "amlogic|s805x|la.?frite" /proc/cpuinfo 2>/dev/null
}

if is_raspberry_pi; then
    log "WARNING: Raspberry Pi detected. This script is tuned for La Frite boards; consider using install/single-native-arcade-setup.sh for a Pi."
fi

if is_la_frite; then
    log "La Frite board detected"
fi

log "Checking meson + lima DRM support..."

# Drivers may be built into the kernel or loaded as modules.
is_driver_present() {
    local name="$1"
    grep -qE "^${name}[[:space:]]" /proc/modules 2>/dev/null && return 0
    [ -d "/sys/module/${name}" ] && return 0
    return 1
}

has_meson=false
has_lima=false
is_driver_present "meson" && has_meson=true
is_driver_present "meson_drm" && has_meson=true
is_driver_present "lima" && has_lima=true

if ! $has_meson || ! $has_lima; then
    log "WARNING: meson display or lima GPU support not detected."
    log "If the game does not draw, try one of these fallbacks before launching:"
    log "    export SDL_RENDER_DRIVER=software"
    log "    export MESA_LOADER_DRIVER_OVERRIDE=lima"
else
    log "meson/lima DRM support looks active"
fi

if ! ls /dev/dri/card* >/dev/null 2>&1; then
    log "WARNING: no DRM device found under /dev/dri/"
    log "Make sure the 64-bit Debian image has the meson/lima drivers enabled and reboot."
fi

# 2. User / permissions
log "Adding $ARCADE_USER to video, input, audio, and gpio groups..."
# Ensure the gpio group exists for /dev/gpiochip* access.
getent group gpio >/dev/null 2>&1 || groupadd gpio 2>/dev/null || true
for group in video input audio gpio; do
    if getent group "$group" >/dev/null 2>&1; then
        usermod -aG "$group" "$ARCADE_USER" 2>/dev/null || \
            log "WARNING: could not add $ARCADE_USER to $group group"
    else
        log "WARNING: group $group does not exist; skipping"
    fi
done

# uinput permission for the GPIO reset keyboard helper
log "Configuring /dev/uinput permissions..."
modprobe uinput || true
if [ ! -f /etc/modules-load.d/uinput.conf ]; then
    echo "uinput" > /etc/modules-load.d/uinput.conf
fi
if [ ! -f /etc/udev/rules.d/99-uinput.rules ]; then
    cat > /etc/udev/rules.d/99-uinput.rules <<'EOF'
KERNEL=="uinput", MODE="0666"
EOF
fi
if [ -f /etc/rc.local ] && ! grep -q "chmod 0666 /dev/uinput" /etc/rc.local; then
    sed -i '/^exit 0/i chmod 0666 /dev/uinput' /etc/rc.local
fi

# GPIO chip permissions for the gpiod reset helper
log "Configuring /dev/gpiochip* permissions..."
getent group gpio >/dev/null 2>&1 || groupadd gpio 2>/dev/null || true
if [ ! -f /etc/udev/rules.d/99-arcade-gpio.rules ]; then
    cat > /etc/udev/rules.d/99-arcade-gpio.rules <<'EOF'
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
EOF
fi
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=gpio 2>/dev/null || true
# Fix the current devices right away so a reboot isn't strictly required.
if [ -e /dev/gpiochip0 ]; then
    chgrp gpio /dev/gpiochip* 2>/dev/null || true
    chmod 0660 /dev/gpiochip* 2>/dev/null || true
fi

# 3. Determine active game
list_valid_games() {
    find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
        local name
        name="$(basename "$d")"
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            echo "  - $name"
        fi
    done
}

if [ -n "$REQUESTED_GAME" ]; then
    if [ ! -x "$GAMES_DIR/$REQUESTED_GAME/Game" ] || [ ! -f "$GAMES_DIR/$REQUESTED_GAME/libpxt.so" ]; then
        log "ERROR: requested game '$REQUESTED_GAME' is missing Game or libpxt.so"
        log "Valid games:"
        list_valid_games
        exit 1
    fi
    GAME_NAME="$REQUESTED_GAME"
else
    GAME_NAME=""
    while IFS= read -r -d '' d; do
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            GAME_NAME="$(basename "$d")"
            break
        fi
    done < <(find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

if [ -z "$GAME_NAME" ]; then
    log "ERROR: no native game found in $GAMES_DIR/<Name>/Game + libpxt.so"
    log "Directories under $GAMES_DIR/:"
    find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^/  - /'
    exit 1
fi

log "Selected game: $GAME_NAME"

# 4. Autologin on tty1
log "Configuring autologin for $ARCADE_USER on tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $ARCADE_USER --noclear %I linux
EOF
chmod 644 /etc/systemd/system/getty@tty1.service.d/autologin.conf

# 5. Auto-launch on login
BASH_PROFILE="$ARCADE_USER_HOME/.bash_profile"
PROFILE="$ARCADE_USER_HOME/.profile"

inject_launcher() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file"
        chown "$ARCADE_USER:$ARCADE_USER" "$file" 2>/dev/null || true
    fi
    if grep -q "single-native-arcade launcher" "$file" 2>/dev/null; then
        # Update the game name and reset pin in the existing launcher block (even if toggled off).
        local tmp
        tmp="$(mktemp)"
        while IFS= read -r line || [ -n "$line" ]; do
            local re_game='^([[:space:]]*#?[[:space:]]*export[[:space:]]+)SINGLE_GAME_NAME="[^"]*"[[:space:]]*$'
            local re_pin='^([[:space:]]*#?[[:space:]]*export[[:space:]]+)GPIO_RESET_PIN="[^"]*"[[:space:]]*$'
            if [[ "$line" =~ $re_game ]]; then
                echo "${BASH_REMATCH[1]}SINGLE_GAME_NAME=\"$GAME_NAME\""
            elif [[ "$line" =~ $re_pin ]]; then
                echo "${BASH_REMATCH[1]}GPIO_RESET_PIN=\"$GPIO_RESET_PIN\""
            else
                echo "$line"
            fi
        done < "$file" > "$tmp"
        mv "$tmp" "$file"
    else
        {
            echo ""
            echo "# single-native-arcade launcher"
            echo "if [ \"\$(tty)\" = \"/dev/tty1\" ]; then"
            echo '  export ARCADE_LOG="$HOME/arcade.log"'
            echo "  export GPIO_RESET_PIN=\"$GPIO_RESET_PIN\""
            echo "  export SINGLE_GAME_NAME=\"$GAME_NAME\""
            echo "  cd \"$RUN_DIR\" || exit 1"
            echo "  exec bash \"$RUN_DIR/launcher.sh\""
            echo "fi"
        } >> "$file"
    fi
}

inject_launcher "$BASH_PROFILE"
inject_launcher "$PROFILE"
chown "$ARCADE_USER:$ARCADE_USER" "$BASH_PROFILE" "$PROFILE" 2>/dev/null || true

# Ensure the launcher block is enabled (in case it was toggled off).
log "Ensuring autolaunch is enabled for $ARCADE_USER..."
su - "$ARCADE_USER" -c "bash '$RUN_DIR/toggle-arcade.sh' enable" 2>/dev/null || \
    log "WARNING: could not enable autolaunch as $ARCADE_USER"

# 6. Set executable bits
chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/single-native-launch.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/toggle-arcade.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/gpio-reset-keyboard.py" 2>/dev/null || true
chmod +x "$RUN_DIR/gpio-reset-keyboard-gpiod.py" 2>/dev/null || true
find "$GAMES_DIR" -maxdepth 2 -type f -name "Game" -exec chmod +x {} \; 2>/dev/null || true
chown -R "$ARCADE_USER:$ARCADE_USER" "$RUN_DIR" 2>/dev/null || true

# 7. Optional HDMI audio fix
if [ -x "$RUN_DIR/install/hdmi-audio-fix.sh" ]; then
    log "HDMI audio fix available at $RUN_DIR/install/hdmi-audio-fix.sh"
fi

log "=== Setup complete ==="
log "Active game:       $GAME_NAME"
log "Checkout directory: $RUN_DIR"
log "Reboot to start:   sudo reboot"
