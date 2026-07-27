#!/bin/bash
# single-native-arcade-setup.sh — one-shot installer for the single native arcade kiosk.
# Run from the checkout directory on the target machine (usually as root).
set -e

REQUESTED_GAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --game=*) REQUESTED_GAME="${1#*=}"; shift ;;
        --game) REQUESTED_GAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--game=GameName]"
            echo "If --game is omitted, the first available native game executable is selected."
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

log "=== single-native-arcade setup ==="
log "Checkout directory: $RUN_DIR"
log "User:               $ARCADE_USER"

# 1. System packages
log "Installing system packages..."
apt-get update
apt-get install -y git libsdl2-2.0-0 libdrm2 libgbm1 libudev1 libasound2

# 2. User / permissions
log "Adding $ARCADE_USER to video, input, and audio groups..."
usermod -aG video,input,audio "$ARCADE_USER" 2>/dev/null || true

# 3. Determine active game
list_valid_games() {
    find "$GAMES_DIR" -maxdepth 1 -type f | sort | while read -r f; do
        local name
        name="$(basename "$f")"
        if [ "$name" = "libpxt.so" ]; then
            continue
        fi
        if [ -x "$f" ]; then
            echo "  - $name"
        fi
    done
}

if [ ! -f "$GAMES_DIR/libpxt.so" ]; then
    log "ERROR: shared library not found: $GAMES_DIR/libpxt.so"
    log "Place the architecture-matching libpxt.so in $GAMES_DIR/ before running setup."
    exit 1
fi

if [ -n "$REQUESTED_GAME" ]; then
    if [ ! -x "$GAMES_DIR/$REQUESTED_GAME" ] || [ -d "$GAMES_DIR/$REQUESTED_GAME" ]; then
        log "ERROR: requested game '$REQUESTED_GAME' is not an executable file in $GAMES_DIR/"
        log "Valid games:"
        list_valid_games
        exit 1
    fi
    GAME_NAME="$REQUESTED_GAME"
else
    GAME_NAME=""
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

if [ -z "$GAME_NAME" ]; then
    log "ERROR: no native game executable found in $GAMES_DIR/"
    log "Files in $GAMES_DIR/:"
    find "$GAMES_DIR" -maxdepth 1 -type f -exec basename {} \; | sed 's/^/  - /'
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
            echo "  cd \"$RUN_DIR\" || exit 1"
            echo "  exec bash \"$RUN_DIR/launcher.sh\""
            echo "fi"
        } >> "$file"
    fi
}

inject_launcher "$BASH_PROFILE"
inject_launcher "$PROFILE"
chown "$ARCADE_USER:$ARCADE_USER" "$BASH_PROFILE" "$PROFILE" 2>/dev/null || true

# 6. Set executable bits
chmod +x "$RUN_DIR/launcher.sh" 2>/dev/null || true
chmod +x "$RUN_DIR/single-native-launch.sh" 2>/dev/null || true
find "$GAMES_DIR" -maxdepth 1 -type f ! -name "libpxt.so" -exec chmod +x {} \; 2>/dev/null || true
chown -R "$ARCADE_USER:$ARCADE_USER" "$RUN_DIR" 2>/dev/null || true

# 7. Optional HDMI audio fix
if [ -x "$RUN_DIR/install/hdmi-audio-fix.sh" ]; then
    log "HDMI audio fix available at $RUN_DIR/install/hdmi-audio-fix.sh"
fi

log "=== Setup complete ==="
log "Active game:       $GAME_NAME"
log "Checkout directory: $RUN_DIR"
log "Reboot to start:   sudo reboot"
