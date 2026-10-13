#!/bin/bash
# multi-native-arcade-setup.sh — one-shot installer for the multi native arcade kiosk.
# Run from the checkout directory on the target machine (usually as root).
# Boots into the menu game (games/Menu/); games are picked from the menu.
set -e

ENABLE_GPIO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --gpio) ENABLE_GPIO=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--gpio]"
            echo "--gpio installs install/arcade.cfg as /etc/arcade.cfg so the Game"
            echo "binary reads arcade buttons wired to the GPIO pins."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

RUN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAMES_DIR="$RUN_DIR/games"

if [ -n "${SUDO_USER:-}" ]; then
    ARCADE_USER="$SUDO_USER"
else
    ARCADE_USER="$(logname 2>/dev/null || id -un || echo pi)"
fi

LOG_FILE="/home/pi/arcade.log"
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

log "=== multi-native-arcade setup ==="
log "Checkout directory: $RUN_DIR"
log "User:               $ARCADE_USER"

# 1. System packages
log "Installing system packages..."
apt-get update
apt-get install -y git libsdl2-2.0-0 libdrm2 libgbm1 libudev1 libasound2 libgl1-mesa-dri libegl1 libgles2 python3-rpi.gpio

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

# 1b. Board-specific GPU setup
is_raspberry_pi() {
    grep -qE "Raspberry Pi|BCM2835|BCM2836|BCM2837|BCM2711|BCM2712" /proc/cpuinfo 2>/dev/null || \
    grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null
}

setup_pi_gpu() {
    local config=""
    for f in /boot/firmware/config.txt /boot/config.txt; do
        if [ -f "$f" ]; then
            config="$f"
            break
        fi
    done
    if [ -z "$config" ]; then
        log "WARNING: Raspberry Pi detected but no boot config.txt found"
        return
    fi
    if ! grep -q "^dtoverlay=vc4-kms-v3d" "$config"; then
        log "Enabling vc4-kms-v3d overlay in $config"
        echo "dtoverlay=vc4-kms-v3d,cma-128" >> "$config"
    else
        log "vc4-kms-v3d overlay already enabled"
    fi
}

if is_raspberry_pi; then
    setup_pi_gpu
fi

# 2. User / permissions
log "Adding $ARCADE_USER to video, input, audio, and gpio groups..."
usermod -aG video,input,audio,gpio "$ARCADE_USER" 2>/dev/null || true

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
BASH_PROFILE="/home/$ARCADE_USER/.bash_profile"
PROFILE="/home/$ARCADE_USER/.profile"

inject_launcher() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file"
        chown "$ARCADE_USER:$ARCADE_USER" "$file" 2>/dev/null || true
    fi
    if grep -q "native-arcade launcher" "$file" 2>/dev/null; then
        # Launcher block already exists; leave it (and its toggle state) alone.
        return 0
    fi
    {
        echo ""
        echo "# multi-native-arcade launcher"
        echo "if [ \"\$(tty)\" = \"/dev/tty1\" ]; then"
        echo "  cd \"$RUN_DIR\" || exit 1"
        echo "  exec bash \"$RUN_DIR/launcher.sh\""
        echo "fi"
    } >> "$file"
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
    if [ -f /etc/arcade.cfg ] && ! cmp -s "$RUN_DIR/install/arcade.cfg" /etc/arcade.cfg; then
        cp /etc/arcade.cfg "/etc/arcade.cfg.bak.$(date +%s)"
        log "Backed up existing /etc/arcade.cfg"
    fi
    cp "$RUN_DIR/install/arcade.cfg" /etc/arcade.cfg
    chmod 644 /etc/arcade.cfg
    log "Installed GPIO button config to /etc/arcade.cfg"
else
    log "GPIO buttons not enabled (pass --gpio to install /etc/arcade.cfg)"
fi

# 5c. USB game update support
# A udev rule starts arcade-usb-update@<dev>.service when a USB filesystem is
# inserted; the script installs the game from the drive and switches to it.
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
find "$GAMES_DIR" -maxdepth 2 -type f -name "Game" -exec chmod +x {} \; 2>/dev/null || true
chown -R "$ARCADE_USER:$ARCADE_USER" "$RUN_DIR" 2>/dev/null || true

# 7. Optional HDMI audio fix
if [ -x "$RUN_DIR/install/hdmi-audio-fix.sh" ]; then
    log "HDMI audio fix available at $RUN_DIR/install/hdmi-audio-fix.sh"
fi

log "=== Setup complete ==="
log "Menu game:         $MENU_NAME ($GAME_COUNT game dirs installed)"
log "Checkout directory: $RUN_DIR"
log "Reboot to start:   sudo reboot"
