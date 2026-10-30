#!/bin/bash
# la-frite-native-arcade-setup.sh — one-shot installer for the La Frite multi native arcade kiosk.
# Run from the checkout directory on the target machine (usually as root).
# Boots into the menu game (games/Menu/); games are picked from the menu.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "ERROR: This script requires bash." >&2
        exit 1
    fi
fi
set -e

REQUESTED_USER=""
REQUESTED_RESET_PIN=""
REQUESTED_RESET_CHIP=""
ENABLE_GPIO=0

while [ $# -gt 0 ]; do
    case "$1" in
        --user=*) REQUESTED_USER="${1#*=}"; shift ;;
        --user) REQUESTED_USER="$2"; shift 2 ;;
        --gpio) ENABLE_GPIO=1; shift ;;
        --gpio-reset-pin=*) REQUESTED_RESET_PIN="${1#*=}"; shift ;;
        --gpio-reset-pin) REQUESTED_RESET_PIN="$2"; shift 2 ;;
        --gpio-reset-chip=*) REQUESTED_RESET_CHIP="${1#*=}"; shift ;;
        --gpio-reset-chip) REQUESTED_RESET_CHIP="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--user=UserName] [--gpio] [--gpio-reset-pin=Pin] [--gpio-reset-chip=Chip]"
            echo "  --user             defaults to SUDO_USER, then the user running sudo, then 'arcade'."
            echo "  --gpio             installs install/arcade-lafite.cfg as /etc/arcade.cfg so the Game"
            echo "                   binary reads arcade buttons wired to the GPIO pins."
            echo "  --gpio-reset-pin   gpiod line name or offset for the cabinet reset button (default 91, header pin 8)."
            echo "  --gpio-reset-chip  gpiochip path or number for the reset button (default gpiochip1)."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

GPIO_RESET_PIN="${REQUESTED_RESET_PIN:-91}"
GPIO_RESET_CHIP="${REQUESTED_RESET_CHIP:-gpiochip1}"

if [ -n "$REQUESTED_USER" ]; then
    ARCADE_USER="$REQUESTED_USER"
elif [ -n "${SUDO_USER:-}" ]; then
    ARCADE_USER="$SUDO_USER"
else
    ARCADE_USER="$(logname 2>/dev/null || echo arcade)"
fi

# On root-default boards (La Frite), logname resolves to root and the whole
# kiosk would run as root. Default to the dedicated 'arcade' user instead;
# pass --user=root to override.
if [ "$ARCADE_USER" = "root" ] && [ -z "$REQUESTED_USER" ]; then
    echo "No --user given and resolved user is root; installing for 'arcade' instead (use --user=root to keep root)."
    ARCADE_USER="arcade"
fi

if ! id -u "$ARCADE_USER" >/dev/null 2>&1; then
    # Phase 1: run once as root to create the kiosk user and point tty1
    # autologin at it. Everything else is installed on the second run, as
    # the new user via sudo, so the checkout lands in the right home.
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: user '$ARCADE_USER' does not exist. Run this installer as root first to create it." >&2
        exit 1
    fi
    echo "=== First-time setup: creating the '$ARCADE_USER' user ==="
    useradd -m -s /bin/bash "$ARCADE_USER" || { echo "ERROR: could not create user '$ARCADE_USER'" >&2; exit 1; }
    # sudo is needed for phase 2, which runs as the new user via sudo.
    apt-get update && apt-get install -y sudo || echo "WARNING: could not install sudo; install it before running the phase-2 install."
    getent group sudo >/dev/null 2>&1 && usermod -aG sudo "$ARCADE_USER" || true
    echo "Set a password for '$ARCADE_USER' (needed for SSH and sudo):"
    passwd "$ARCADE_USER" || echo "WARNING: no password set; run 'passwd $ARCADE_USER' before rebooting."
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $ARCADE_USER --noclear %I linux
EOF
    chmod 644 /etc/systemd/system/getty@tty1.service.d/autologin.conf
    cat <<MSG

===============================================================
User '$ARCADE_USER' is ready and tty1 will autologin as that user.
Next steps:

  1. reboot
     (you'll land on an $ARCADE_USER shell)
  2. git clone <this repo> && cd CreationStationArcade
  3. sudo bash install/la-frite-native-arcade-setup.sh --gpio

That second run installs everything else: packages, GPIO config,
USB updates, and the game autolaunch.
===============================================================
MSG
    exit 0
fi

ARCADE_USER_HOME="$(getent passwd "$ARCADE_USER" | cut -d: -f6)"
if [ -z "$ARCADE_USER_HOME" ]; then
    ARCADE_USER_HOME="/home/$ARCADE_USER"
    echo "WARNING: could not look up home directory for $ARCADE_USER; using $ARCADE_USER_HOME" >&2
fi

RUN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAMES_DIR="$RUN_DIR/games"

# If the checkout isn't inside the arcade user's home (e.g. cloned to /root
# on a root-login board), copy it there — the autologin user can't read
# /root, so the launcher would die on `cd $RUN_DIR`.
case "$RUN_DIR" in
    "$ARCADE_USER_HOME/"*) ;;
    *)
        TARGET_DIR="$ARCADE_USER_HOME/$(basename "$RUN_DIR")"
        echo "Checkout is outside $ARCADE_USER's home; copying to $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        cp -a "$RUN_DIR/." "$TARGET_DIR/"
        chown -R "$ARCADE_USER:$ARCADE_USER" "$TARGET_DIR" 2>/dev/null || true
        RUN_DIR="$TARGET_DIR"
        GAMES_DIR="$RUN_DIR/games"
        ;;
esac
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
log "Reset pin:          $GPIO_RESET_CHIP:$GPIO_RESET_PIN"

# 1. System packages
log "Installing system packages..."
apt-get update
apt-get install -y sudo git libsdl2-2.0-0 libdrm2 libgbm1 libudev1 libasound2 libgl1-mesa-dri libegl1 libgles2 python3-libgpiod

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
    log "WARNING: Raspberry Pi detected. This script is tuned for La Frite boards; consider using install/multi-native-arcade-setup.sh for a Pi."
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
for group in video input audio gpio sudo; do
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

# 3. Sanity-check installed games
MENU_NAME="${ARCADE_MENU_NAME:-Menu}"
GAME_COUNT=0
while IFS= read -r -d '' d; do
    if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
        GAME_COUNT=$((GAME_COUNT + 1))
        log "  found game: $(basename "$d")"
    fi
done < <(find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

if [ ! -x "$GAMES_DIR/$MENU_NAME/Game" ] || [ ! -f "$GAMES_DIR/$MENU_NAME/libpxt.so" ]; then
    log "WARNING: no menu game at $GAMES_DIR/$MENU_NAME (Game + libpxt.so)."
    log "The cabinet will fall back to ControllerTest or the first installed game."
    log "Build the menu project with the menu-enabled compiler and extract it to games/$MENU_NAME/."
fi
if [ "$GAME_COUNT" -eq 0 ]; then
    log "ERROR: no native game found in $GAMES_DIR/<Name>/Game + libpxt.so"
    log "Directories under $GAMES_DIR/:"
    find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^/  - /'
    exit 1
fi

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
    if grep -q "native-arcade launcher" "$file" 2>/dev/null; then
        # Update the reset pin in the existing launcher block (even if toggled off).
        local tmp
        tmp="$(mktemp)"
        while IFS= read -r line || [ -n "$line" ]; do
            local re_pin='^([[:space:]]*#?[[:space:]]*export[[:space:]]+)GPIO_RESET_PIN="[^"]*"[[:space:]]*$'
            local re_chip='^([[:space:]]*#?[[:space:]]*export[[:space:]]+)GPIO_RESET_CHIP="[^"]*"[[:space:]]*$'
            local re_cd='^([[:space:]]*#?[[:space:]]*cd[[:space:]]+)"[^"]*"[[:space:]]*'
            local re_exec='^([[:space:]]*#?[[:space:]]*exec[[:space:]]+bash[[:space:]]+)"[^"]*launcher\.sh"[[:space:]]*$'
            if [[ "$line" =~ $re_pin ]]; then
                echo "${BASH_REMATCH[1]}GPIO_RESET_PIN=\"$GPIO_RESET_PIN\""
            elif [[ "$line" =~ $re_chip ]]; then
                echo "${BASH_REMATCH[1]}GPIO_RESET_CHIP=\"$GPIO_RESET_CHIP\""
            elif [[ "$line" =~ $re_cd ]]; then
                echo "${BASH_REMATCH[1]}\"$RUN_DIR\" || exit 1"
            elif [[ "$line" =~ $re_exec ]]; then
                echo "${BASH_REMATCH[1]}\"$RUN_DIR/launcher.sh\""
            else
                echo "$line"
            fi
        done < "$file" > "$tmp"
        mv "$tmp" "$file"
    else
        {
            echo ""
            echo "# multi-native-arcade launcher"
            echo "if [ \"\$(tty)\" = \"/dev/tty1\" ]; then"
            echo '  export ARCADE_LOG="$HOME/arcade.log"'
            echo "  export GPIO_RESET_PIN=\"$GPIO_RESET_PIN\""
            echo "  export GPIO_RESET_CHIP=\"$GPIO_RESET_CHIP\""
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

# 5b. GPIO button config (optional)
# The Game binary reads /etc/arcade.cfg at startup; when present, GPIO pins
# listed there become player buttons (edge-triggered, no polling).
if [ "$ENABLE_GPIO" = "1" ]; then
    if [ -f /etc/arcade.cfg ] && ! cmp -s "$RUN_DIR/install/arcade-lafite.cfg" /etc/arcade.cfg; then
        cp /etc/arcade.cfg "/etc/arcade.cfg.bak.$(date +%s)"
        log "Backed up existing /etc/arcade.cfg"
    fi
    cp "$RUN_DIR/install/arcade-lafite.cfg" /etc/arcade.cfg
    chmod 644 /etc/arcade.cfg
    log "Installed La Frite GPIO button config to /etc/arcade.cfg"
else
    log "GPIO buttons not enabled (pass --gpio to install /etc/arcade.cfg)"
fi

# 5c. USB game update support
# A udev rule starts arcade-usb-update@<dev>.service when a USB filesystem is
# inserted; the script installs arcade-game/ from the drive and reboots.
log "Installing USB game-update support..."
cp "$RUN_DIR/install/arcade-usb-update.sh" /usr/local/sbin/arcade-usb-update.sh
chmod 755 /usr/local/sbin/arcade-usb-update.sh
cp "$RUN_DIR/install/arcade-usb-update@.service" /etc/systemd/system/arcade-usb-update@.service
chmod 644 /etc/systemd/system/arcade-usb-update@.service
cp "$RUN_DIR/install/99-arcade-usb.rules" /etc/udev/rules.d/99-arcade-usb.rules
chmod 644 /etc/udev/rules.d/99-arcade-usb.rules
cat > /etc/arcade-usb-update.conf <<EOF
RUN_DIR="$RUN_DIR"
ARCADE_USER="$ARCADE_USER"
EOF
chmod 644 /etc/arcade-usb-update.conf
udevadm control --reload-rules 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# 6. Set executable bits
chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/launch-game.sh" 2>/dev/null || true
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
log "Menu game:         $MENU_NAME ($GAME_COUNT game dirs installed)"
log "Checkout directory: $RUN_DIR"
log ""
log "***************************************************************"
log "*  REQUIRED: set the $ARCADE_USER password for SSH/sudo:"
log "*      passwd $ARCADE_USER"
log "*  Without it you cannot SSH in or kill the kiosk remotely."
log "***************************************************************"
log "Reboot to start:   sudo reboot"
