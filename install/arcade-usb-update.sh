#!/bin/bash
# arcade-usb-update.sh — install a game from a USB stick and switch to it.
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# No reboot is needed: the new game is written to games/<Name>/, the active
# game marker ($RUN_DIR/.active-game) is updated for this boot and the next,
# and the currently running Game (if any) is killed — launcher.sh restarts
# with the new game.
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
#
# Freshness: each installed game gets a .usb-source-mtime stamp recording the
# newest mtime seen on the stick. If the same game is already installed AND
# is the active game AND the stick isn't newer, the stick is ignored — that
# also stops the boot-loop where a stick left inserted kept triggering
# reinstalls and reboots.

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
# Newest candidate wins: compare the newest file inside arcade-game/ with the
# mtimes of the .tar.gz files at the drive root and pick the freshest.
GAME_NAME=""
SRC=""
SRC_MTIME=0

DIR_MTIME=0
if [ -d "$MNT/arcade-game" ]; then
    DIR_MTIME="$(find "$MNT/arcade-game" -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -n1 | cut -d. -f1)"
    DIR_MTIME="${DIR_MTIME:-0}"
fi

TARBALL=""
TAR_MTIME=0
NEWEST_TAR="$(find "$MNT" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' ! -name '.*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1)"
if [ -n "$NEWEST_TAR" ]; then
    TAR_MTIME="${NEWEST_TAR%% *}"
    TAR_MTIME="${TAR_MTIME%%.*}"
    TARBALL="${NEWEST_TAR#* }"
fi

if [ -d "$MNT/arcade-game" ] && [ "$DIR_MTIME" -ge "$TAR_MTIME" ]; then
    mkdir -p "$STAGE/game"
    cp -a "$MNT/arcade-game/." "$STAGE/game/"
    SRC="$STAGE/game"
    SRC_LABEL="arcade-game/"
    SRC_MTIME="$DIR_MTIME"
elif [ -n "$TARBALL" ]; then
    # Try tarballs newest-first; a bad one falls through to the next.
    while IFS= read -r cand && [ -z "$SRC" ]; do
        [ -n "$cand" ] || continue
        SRC_MTIME="${cand%% *}"
        SRC_MTIME="${SRC_MTIME%%.*}"
        TARBALL="${cand#* }"
        SRC_LABEL="$(basename "$TARBALL")"
        # Validate BEFORE extracting: the archive must list Game and libpxt.so
        # somewhere inside, and must not contain absolute paths or ../
        # traversal entries. A random tarball fails here without touching disk.
        LISTING="$(tar tzf "$TARBALL" 2>/dev/null || true)"
        if [ -z "$LISTING" ]; then
            log "found $SRC_LABEL but it is not a readable tar.gz; trying next"
            continue
        fi
        if echo "$LISTING" | grep -qE '^(/|\.\./)|/\.\./'; then
            log "found $SRC_LABEL but it contains unsafe paths (absolute or ../); trying next"
            continue
        fi
        if ! echo "$LISTING" | grep -qE '(^|/)Game$' || ! echo "$LISTING" | grep -qE '(^|/)libpxt\.so$'; then
            log "found $SRC_LABEL but it has no Game + libpxt.so inside; trying next"
            continue
        fi
        mkdir -p "$STAGE/tar"
        if ! tar xzf "$TARBALL" -C "$STAGE/tar" 2>/dev/null; then
            log "found $SRC_LABEL but could not extract it; trying next"
            rm -rf "$STAGE/tar"
            continue
        fi
        # Locate the dir holding Game + libpxt.so (archive may nest them).
        SRC="$(dirname "$(find "$STAGE/tar" -name Game -type f | head -n1)" 2>/dev/null)"
        [ -f "$SRC/Game" ] && [ -f "$SRC/libpxt.so" ] || SRC=""
        # Name from the filename: strip .tar.gz and any -arch suffix.
        GAME_NAME="$(basename "$TARBALL" .tar.gz | sed -E 's/-(arm64|x86-64|win64|amd64)$//' | tr -cd 'A-Za-z0-9._-')"
    done < <(find "$MNT" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' ! -name '.*' -printf '%T@ %p\n' 2>/dev/null | sort -nr)
fi

if [ -z "$SRC" ]; then
    log "no arcade-game/ folder or .tar.gz with Game + libpxt.so on $DEV; ignoring"
    exit 0
fi

log "found game source: $SRC_LABEL"

# Sanity: Game and libpxt.so must be real ELF binaries, not just files that
# happen to have the right names.
is_elf() {
    [ "$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "7f454c46" ]
}
if ! is_elf "$SRC/Game" || ! is_elf "$SRC/libpxt.so"; then
    log "Game or libpxt.so is not an ELF binary; ignoring"
    exit 0
fi

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

SRC_MTIME="${SRC_MTIME:-0}"
ACTIVE_FILE="$RUN_DIR/.active-game"
CURRENT_ACTIVE=""
[ -f "$ACTIVE_FILE" ] && CURRENT_ACTIVE="$(head -n1 "$ACTIVE_FILE" | tr -cd 'A-Za-z0-9._-')"
# Machines installed before .active-game existed carry the name in the profile.
if [ -z "$CURRENT_ACTIVE" ]; then
    CURRENT_ACTIVE="$(grep -oE 'SINGLE_GAME_NAME="[^"]*"' "/home/$ARCADE_USER/.bash_profile" "/home/$ARCADE_USER/.profile" 2>/dev/null | head -n1 | cut -d'"' -f2)"
fi
DEST="$GAMES_DIR/$GAME_NAME"
STAMP="$DEST/.usb-source-mtime"
INSTALLED_MTIME=0
[ -f "$STAMP" ] && INSTALLED_MTIME="$(cat "$STAMP" 2>/dev/null || echo 0)"

# Skip when the stick carries the same game we already installed, it isn't
# newer than what we have, and it's the game currently running. Stops the
# reboot-loop when a stick is left inserted.
if [ "$CURRENT_ACTIVE" = "$GAME_NAME" ] && [ -d "$DEST" ] && [ "$SRC_MTIME" -le "$INSTALLED_MTIME" ]; then
    log "'$GAME_NAME' already installed and active (stick mtime $SRC_MTIME <= installed $INSTALLED_MTIME); ignoring"
    exit 0
fi

log "installing '$GAME_NAME' from $DEV into $GAMES_DIR"

# Stage the new game dir, then swap it into place so a running Game never
# sees a half-copied folder.
FINAL="$STAGE/final"
mkdir -p "$FINAL"
cp -a "$SRC/Game" "$SRC/libpxt.so" "$FINAL/"
chmod +x "$FINAL/Game"
# Copy any extra assets the game ships (data files, etc.) alongside the binary.
find "$SRC" -mindepth 1 -maxdepth 1 ! -name Game ! -name libpxt.so ! -name name.txt ! -name arcade.cfg \
    ! -name '.*' -exec cp -a {} "$FINAL/" \; 2>/dev/null || true
echo "$SRC_MTIME" > "$FINAL/.usb-source-mtime"

rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$FINAL" "$DEST"
rm -rf "$DEST.old"

# Drop any other installed games so a stale folder can't become the
# fallback pick. ControllerTest stays — it's the "does this thing work"
# sanity game.
find "$GAMES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "$GAME_NAME" ! -name ControllerTest -exec rm -rf {} +

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

# Point the live launcher at the new game too. launcher.sh re-reads
# .active-game each loop, so killing the running Game swaps us over
# without a reboot (and the profiles above keep it across real reboots).
echo "$GAME_NAME" > "$ACTIVE_FILE"
chown "$ARCADE_USER:$ARCADE_USER" "$ACTIVE_FILE" 2>/dev/null || true

sync

GAME_PID=""
[ -f /tmp/creationstation_current_game.pid ] && GAME_PID="$(cat /tmp/creationstation_current_game.pid 2>/dev/null || true)"
if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
    log "switching live: killing running Game (pid $GAME_PID); launcher will restart '$GAME_NAME'"
    kill "$GAME_PID" 2>/dev/null || true
else
    log "no running Game found; '$GAME_NAME' starts on next launch"
fi
log "done; active game is now '$GAME_NAME'"
