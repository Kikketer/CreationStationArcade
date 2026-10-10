#!/bin/bash
# arcade-usb-update.sh — install a game from a USB stick and reboot.
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# USB format — either of these at the drive root:
#   *.tar.gz        — the archive straight from the PNG to Desktop compiler
#                     (must contain Game + libpxt.so at any depth; an optional
#                     name.txt inside sets the games/<Name>, otherwise the
#                     name comes from the filename)
#   arcade-game/    — an already-extracted folder with Game + libpxt.so
#                     (optional name.txt, arcade.cfg for GPIO buttons)
#
# /etc/arcade-usb-update.conf (written by the installer) provides:
#   RUN_DIR      — checkout directory containing games/
#   ARCADE_USER  — user that owns the games and runs the launcher

set -u

DEV="${1:-}"
CONF=/etc/arcade-usb-update.conf
RUN_DIR=""
ARCADE_USER="pi"
[ -f "$CONF" ] && . "$CONF"

LOG_FILE="${ARCADE_LOG:-/home/pi/arcade.log}"
MNT=/mnt/arcade-usb
STAGE="$(mktemp -d)"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] usb-update: $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] usb-update: $*" >> "$LOG_FILE" 2>/dev/null || true
}

fail() {
    log "ERROR: $*"
    exit 1
}

if [ -z "$DEV" ]; then
    echo "Usage: $0 <block-device>" >&2
    exit 2
fi

[ -n "$RUN_DIR" ] && [ -d "$RUN_DIR/games" ] || fail "RUN_DIR not configured (missing $CONF); re-run the installer"
GAMES_DIR="$RUN_DIR/games"

log "checking $DEV for an arcade game"

mkdir -p "$MNT"

# The filesystem may need a moment to settle after the udev add event.
MOUNTED=0
for _ in 1 2 3 4 5; do
    if mount -o ro "$DEV" "$MNT" 2>/dev/null; then
        MOUNTED=1
        break
    fi
    sleep 1
done

cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

if [ "$MOUNTED" != "1" ]; then
    log "could not mount $DEV; ignoring"
    exit 0
fi

# --- Stage the game from the stick ---
GAME_NAME=""
SRC=""

if [ -d "$MNT/arcade-game" ]; then
    mkdir -p "$STAGE/game"
    cp -a "$MNT/arcade-game/." "$STAGE/game/"
    SRC="$STAGE/game"
    SRC_LABEL="arcade-game/"
else
    # First .tar.gz at the stick root wins (e.g. MyGame-arm64.tar.gz).
    TARBALL="$(find "$MNT" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' ! -name '.*' | LC_ALL=C sort | head -n1)"
    if [ -n "$TARBALL" ]; then
        mkdir -p "$STAGE/tar"
        if tar xzf "$TARBALL" -C "$STAGE/tar" 2>/dev/null; then
            # Locate the dir holding Game + libpxt.so (archive may nest them).
            SRC="$(dirname "$(find "$STAGE/tar" -name Game -type f | head -n1)" 2>/dev/null)"
            [ -f "$SRC/Game" ] && [ -f "$SRC/libpxt.so" ] || SRC=""
            SRC_LABEL="$(basename "$TARBALL")"
            # Name from the filename: strip .tar.gz and any -arch suffix.
            GAME_NAME="$(basename "$TARBALL" .tar.gz | sed -E 's/-(arm64|x86-64|win64|amd64)$//' | tr -cd 'A-Za-z0-9._-')"
        else
            log "found $TARBALL but could not extract it; ignoring"
            exit 0
        fi
    fi
fi

if [ -z "$SRC" ]; then
    log "no arcade-game/ folder or .tar.gz with Game + libpxt.so on $DEV; ignoring"
    exit 0
fi

log "found game source: $SRC_LABEL"

# name.txt inside the game folder overrides the filename-derived name.
if [ -f "$SRC/name.txt" ]; then
    OVERRIDE="$(head -n1 "$SRC/name.txt" | tr -cd 'A-Za-z0-9._-')"
    [ -n "$OVERRIDE" ] && GAME_NAME="$OVERRIDE"
fi
[ -n "$GAME_NAME" ] || GAME_NAME="USBGame"

# Architecture check: refuse a binary that can't run here.
if command -v file >/dev/null 2>&1; then
    MACHINE="$(uname -m)"
    DESC="$(file -b "$SRC/Game" 2>/dev/null || true)"
    case "$MACHINE" in
        aarch64|arm64) PAT="aarch64|ARM aarch64|ARM64" ;;
        x86_64|amd64)  PAT="x86-64" ;;
        *)             PAT="" ;;
    esac
    if [ -n "$PAT" ] && ! echo "$DESC" | grep -qiE "$PAT"; then
        fail "Game binary is not built for $MACHINE ($DESC); keeping current game"
    fi
fi

log "installing '$GAME_NAME' from $DEV into $GAMES_DIR"

DEST="$GAMES_DIR/$GAME_NAME"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC/Game" "$SRC/libpxt.so" "$DEST/"
chmod +x "$DEST/Game"
# Copy any extra assets the game ships (data files, etc.) alongside the binary.
find "$SRC" -mindepth 1 -maxdepth 1 ! -name Game ! -name libpxt.so ! -name name.txt ! -name arcade.cfg \
    ! -name '.*' -exec cp -a {} "$DEST/" \; 2>/dev/null || true
chown -R "$ARCADE_USER:$ARCADE_USER" "$DEST" 2>/dev/null || true

# Optional GPIO button config on the stick.
if [ -f "$SRC/arcade.cfg" ]; then
    if [ -f /etc/arcade.cfg ] && ! cmp -s "$SRC/arcade.cfg" /etc/arcade.cfg; then
        cp /etc/arcade.cfg "/etc/arcade.cfg.bak.$(date +%s)"
    fi
    cp "$SRC/arcade.cfg" /etc/arcade.cfg
    chmod 644 /etc/arcade.cfg
    log "installed arcade.cfg from USB"
fi

# Point the launcher at the new game: rewrite SINGLE_GAME_NAME in the existing
# launcher block, or append the block if the profile was never set up.
set_game_name() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file"
        chown "$ARCADE_USER:$ARCADE_USER" "$file" 2>/dev/null || true
    fi
    if grep -q "single-native-arcade launcher" "$file" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^([[:space:]]*#?[[:space:]]*export[[:space:]]+)SINGLE_GAME_NAME=\"[^\"]*\"[[:space:]]*$ ]]; then
                echo "${BASH_REMATCH[1]}SINGLE_GAME_NAME=\"$GAME_NAME\""
            else
                echo "$line"
            fi
        done < "$file" > "$tmp"
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
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

set_game_name "/home/$ARCADE_USER/.bash_profile"
set_game_name "/home/$ARCADE_USER/.profile"

sync
log "done; rebooting into '$GAME_NAME'"
sleep 1
systemctl reboot
