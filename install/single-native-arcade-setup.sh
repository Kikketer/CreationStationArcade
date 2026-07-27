#!/bin/bash
# single-native-arcade-setup.sh — one-shot installer for the single native arcade kiosk.
# Run from the source repo root on the target machine (usually as root).
set -e

REQUESTED_GAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --game=*) REQUESTED_GAME="${1#*=}"; shift ;;
        --game) REQUESTED_GAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--game=GameName]"
            echo "If --game is omitted, the first available native game is selected."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

LOG_FILE="/home/pi/arcade.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true
chown "$ARCADE_USER:$ARCADE_USER" "$LOG_FILE" 2>/dev/null || true

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Runtime folder is the source folder with a trailing "-src" removed, or a default.
case "$SOURCE_DIR" in
    *-src) RUN_DIR="${SOURCE_DIR%-src}" ;;
    *) RUN_DIR="/home/pi/CreationStationArcade" ;;
esac

if [ -n "${SUDO_USER:-}" ]; then
    ARCADE_USER="$SUDO_USER"
else
    ARCADE_USER="$(logname 2>/dev/null || id -un || echo pi)"
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This installer must be run as root (try: sudo $0)" >&2
    exit 1
fi

log "=== single-native-arcade setup ==="
log "Source:   $SOURCE_DIR"
log "Runtime:  $RUN_DIR"
log "User:     $ARCADE_USER"

# 1. System packages
log "Installing system packages..."
apt-get update
apt-get install -y git rsync python3 libsdl2-2.0-0 libdrm2 libgbm1 libudev1 libasound2 fbi

# 2. User / permissions
log "Adding $ARCADE_USER to video, input, audio, and gpio groups..."
getent group gpio >/dev/null || groupadd gpio 2>/dev/null || true
usermod -aG video,input,audio,gpio "$ARCADE_USER" 2>/dev/null || true

modprobe uinput 2>/dev/null || true
modprobe joydev 2>/dev/null || true
if ! grep -q "^uinput$" /etc/modules 2>/dev/null; then echo "uinput" >> /etc/modules; fi
if ! grep -q "^joydev$" /etc/modules 2>/dev/null; then echo "joydev" >> /etc/modules; fi

# 3. Determine active game
list_valid_games() {
    find "$SOURCE_DIR/games" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
        local name
        name="$(basename "$d")"
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            echo "  - $name"
        fi
    done
}

all_games=$(find "$SOURCE_DIR/games" -mindepth 1 -maxdepth 1 -type d | sort)

if [ -n "$REQUESTED_GAME" ]; then
    if [ ! -x "$SOURCE_DIR/games/$REQUESTED_GAME/Game" ] || [ ! -f "$SOURCE_DIR/games/$REQUESTED_GAME/libpxt.so" ]; then
        log "ERROR: requested game '$REQUESTED_GAME' is missing Game or libpxt.so"
        log "Valid games:"
        list_valid_games
        exit 1
    fi
    GAME_NAME="$REQUESTED_GAME"
else
    GAME_NAME=""
    for d in $all_games; do
        if [ -x "$d/Game" ] && [ -f "$d/libpxt.so" ]; then
            GAME_NAME="$(basename "$d")"
            break
        fi
    done
fi

if [ -z "$GAME_NAME" ]; then
    log "ERROR: no native game found in $SOURCE_DIR/games/*/Game + libpxt.so"
    log "Directories under $SOURCE_DIR/games:"
    find "$SOURCE_DIR/games" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^/  - /'
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
BASH_PROFILE="/home/$ARCADE_USER/.bash_profile"
PROFILE="/home/$ARCADE_USER/.profile"

inject_launcher() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file"
        chown "$ARCADE_USER:$ARCADE_USER" "$file" 2>/dev/null || true
    fi
    if ! grep -q "single-native-arcade launcher" "$file" 2>/dev/null; then
        {
            echo ""
            echo "# single-native-arcade launcher"
            echo "if [ \"\$(tty)\" = \"/dev/tty1\" ]; then"
            echo "  export SINGLE_GAME_NAME=\"$GAME_NAME\""
            echo "  export CSA_SOURCE_DIR=\"$SOURCE_DIR\""
            echo "  cd \"$RUN_DIR\" || exit 1"
            echo "  exec bash \"$RUN_DIR/launcher.sh\""
            echo "fi"
        } >> "$file"
    fi
}

inject_launcher "$BASH_PROFILE"
inject_launcher "$PROFILE"
chown "$ARCADE_USER:$ARCADE_USER" "$BASH_PROFILE" "$PROFILE" 2>/dev/null || true

# 6. Runtime sync
log "Creating runtime folder and syncing source..."
mkdir -p "$RUN_DIR"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude "arcade.log" "$SOURCE_DIR"/ "$RUN_DIR"/
else
    cp -a "$SOURCE_DIR"/. "$RUN_DIR"/
fi

chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/single-native-launch.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/monitor_kill.py" 2>/dev/null || true
find "$RUN_DIR/games" -maxdepth 2 -type f -name "Game" -exec chmod +x {} \; 2>/dev/null || true
chown -R "$ARCADE_USER:$ARCADE_USER" "$RUN_DIR" 2>/dev/null || true

# 7. Reset monitor service
MONITOR_SERVICE_SRC="$SOURCE_DIR/install/etc/systemd/system/arcade-monitor.service"
if [ -f "$MONITOR_SERVICE_SRC" ]; then
    log "Installing arcade-monitor.service..."
    cp "$MONITOR_SERVICE_SRC" /etc/systemd/system/arcade-monitor.service
    sed -i "s|{{RUN_DIR}}|$RUN_DIR|g; s|{{ARCADE_USER}}|$ARCADE_USER|g; s|{{SINGLE_GAME_NAME}}|$GAME_NAME|g" /etc/systemd/system/arcade-monitor.service
    chmod 644 /etc/systemd/system/arcade-monitor.service
    systemctl daemon-reload
    systemctl enable arcade-monitor.service
else
    log "WARNING: arcade-monitor.service not found at $MONITOR_SERVICE_SRC"
fi

# 8. Splash / boot cosmetics
if [ -x "$SOURCE_DIR/install/splash-setup.sh" ]; then
    log "Running splash setup..."
    "$SOURCE_DIR/install/splash-setup.sh" || true
else
    log "WARNING: splash-setup.sh not found; skipping splash setup"
fi

if [ -x "$SOURCE_DIR/install/hdmi-audio-fix.sh" ]; then
    log "HDMI audio fix available at $SOURCE_DIR/install/hdmi-audio-fix.sh"
fi

log "=== Setup complete ==="
log "Active game:       $GAME_NAME"
log "Runtime directory: $RUN_DIR"
log "Reboot to start:   sudo reboot"
