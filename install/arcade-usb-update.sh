#!/bin/bash
# arcade-usb-update.sh — install a game from a USB stick and reboot.
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# USB format: a directory named "arcade-game" at the drive root containing:
#   Game        — the native MakeCode Arcade binary (required)
#   libpxt.so   — the runtime library (required)
#   name.txt    — single-line game name for games/<Name> (optional)
#   arcade.cfg  — GPIO button config, copied to /etc/arcade.cfg (optional)
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
}
trap cleanup EXIT

if [ "$MOUNTED" != "1" ]; then
    log "could not mount $DEV; ignoring"
    exit 0
fi

SRC="$MNT/arcade-game"
if [ ! -f "$SRC/Game" ] || [ ! -f "$SRC/libpxt.so" ]; then
    log "no arcade-game/ directory with Game + libpxt.so on $DEV; ignoring"
    exit 0
fi

# Cartridge signature: the game is bound to this stick's filesystem UUID.
# signature.txt = sha256("arcade-cart-v1", uuid, per-file hashes) written by
# pack-usb.sh. A copied arcade-game/ on a different stick fails this check.
# Set ALLOW_UNSIGNED=1 in /etc/arcade-usb-update.conf to accept unsigned carts.
sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# signature.txt schemes:
#   v1:<hash> (or a bare hash) — bound to the stick's filesystem UUID,
#      written by install/pack-usb.sh
#   v2:<hash> — bound to a random key file (.arcade-cart-key) at the stick
#      root, written by the desktop compiler's "USB cartridge" option.
#      Copying arcade-game/ to another stick leaves the key file behind.
expected_signature() {
    local version="$1" secret
    case "$version" in
        v1)
            secret="$(blkid -o value -s UUID "$DEV" 2>/dev/null || true)"
            ;;
        v2)
            secret="$(cat "$MNT/.arcade-cart-key" 2>/dev/null | tr -d '[:space:]')"
            ;;
        *) return 1 ;;
    esac
    [ -n "$secret" ] || return 1
    {
        echo "arcade-cart-$version"
        echo "$secret"
        find "$SRC" -mindepth 1 -maxdepth 1 -type f ! -name signature.txt ! -name '.*' \
            | LC_ALL=C sort | while read -r f; do
                h="$(sha "$f" | awk '{print $1}')"
                echo "$h  $(basename "$f")"
            done
    } | sha | awk '{print $1}'
}

if [ "${ALLOW_UNSIGNED:-0}" != "1" ]; then
    ACTUAL="$(cat "$SRC/signature.txt" 2>/dev/null | tr -d '[:space:]')"
    case "$ACTUAL" in
        v2:*) VERSION="v2"; ACTUAL="${ACTUAL#v2:}" ;;
        v1:*) VERSION="v1"; ACTUAL="${ACTUAL#v1:}" ;;
        *)    VERSION="v1" ;;
    esac
    EXPECTED="$(expected_signature "$VERSION" || true)"
    if [ -z "$EXPECTED" ] || [ -z "$ACTUAL" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
        log "arcade-game/ signature missing or not valid for this stick; refusing"
        exit 0
    fi
    log "cartridge signature verified ($VERSION)"
fi

# Game name: name.txt (sanitized) or a default.
GAME_NAME=""
if [ -f "$SRC/name.txt" ]; then
    GAME_NAME="$(head -n1 "$SRC/name.txt" | tr -cd 'A-Za-z0-9._-')"
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
    ! -name signature.txt ! -name '.*' -exec cp -a {} "$DEST/" \; 2>/dev/null || true
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
