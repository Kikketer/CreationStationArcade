#!/bin/bash
# arcade-usb-update.sh — install a game from a USB stick and switch to it.
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# No reboot is needed: the new game is added to games/<Name>/ alongside the
# others, a launch request is written for launcher.sh, and the currently
# running Game (menu or game) is killed — launcher.sh starts the new game.
# On the next boot the menu comes up first and the new game is in the list.
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# USB format — either of these at the drive root:
#   *.tar.gz        — the archive straight from the PNG to Desktop compiler
#                     (must contain Game + libpxt.so at any depth; an optional
#                     name.txt inside sets the games/<Name>, otherwise the
#                     name comes from the filename). Neighboring files with
#                     the same basename become menu assets:
#                     <Name>.png -> cover.png, <Name>.img -> cover.img,
#                     <Name>.json -> info.json
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

ARCADE_USER_HOME="$(getent passwd "$ARCADE_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$ARCADE_USER_HOME" ] || ARCADE_USER_HOME="/home/$ARCADE_USER"

LOG_FILE="${ARCADE_LOG:-$ARCADE_USER_HOME/arcade.log}"
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

# --- Install one game dir ---
# Args: SRC GAME_NAME SRC_MTIME TARBALL SRC_LABEL
# Returns 0=installed, 2=already present, 1=rejected. RESULT_NAME carries the
# resolved games/<Name> either way when usable.
install_game() {
    local SRC="$1" GAME_NAME="$2" SRC_MTIME="$3" TARBALL="$4" SRC_LABEL="$5"
    RESULT_NAME=""

    log "found game source: $SRC_LABEL"

    # Sanity: Game and libpxt.so must be real ELF binaries, not just files
    # that happen to have the right names.
    if ! is_elf "$SRC/Game" || ! is_elf "$SRC/libpxt.so"; then
        log "Game or libpxt.so is not an ELF binary; ignoring"
        return 1
    fi

    # name.txt inside the game folder overrides the filename-derived name.
    if [ -f "$SRC/name.txt" ]; then
        local OVERRIDE
        OVERRIDE="$(head -n1 "$SRC/name.txt" | tr -cd 'A-Za-z0-9._-')"
        [ -n "$OVERRIDE" ] && GAME_NAME="$OVERRIDE"
    fi
    [ -n "$GAME_NAME" ] || GAME_NAME="USBGame"
    RESULT_NAME="$GAME_NAME"

    # Architecture check: refuse a binary that can't run here.
    if command -v file >/dev/null 2>&1; then
        local MACHINE DESC PAT
        MACHINE="$(uname -m)"
        DESC="$(file -b "$SRC/Game" 2>/dev/null || true)"
        case "$MACHINE" in
            aarch64|arm64) PAT="aarch64|ARM aarch64|ARM64" ;;
            x86_64|amd64)  PAT="x86-64" ;;
            *)             PAT="" ;;
        esac
        if [ -n "$PAT" ] && ! echo "$DESC" | grep -qiE "$PAT"; then
            log "Game binary is not built for $MACHINE ($DESC); skipping '$GAME_NAME'"
            return 1
        fi
    fi

    SRC_MTIME="${SRC_MTIME:-0}"
    local DEST="$GAMES_DIR/$GAME_NAME" STAMP INSTALLED_MTIME=0
    STAMP="$DEST/.usb-source-mtime"
    [ -f "$STAMP" ] && INSTALLED_MTIME="$(cat "$STAMP" 2>/dev/null || echo 0)"

    # Skip when the stick carries the same game we already installed and it
    # isn't newer than what we have. Stops the reinstall-loop when a stick is
    # left inserted.
    if [ -d "$DEST" ] && [ "$SRC_MTIME" -le "$INSTALLED_MTIME" ]; then
        log "'$GAME_NAME' already installed (stick mtime $SRC_MTIME <= installed $INSTALLED_MTIME); skipping"
        return 2
    fi

    log "installing '$GAME_NAME' from $DEV into $GAMES_DIR"

    # Stage the new game dir, then swap it into place so a running Game never
    # sees a half-copied folder.
    local FINAL="$STAGE/final-$GAME_NAME"
    mkdir -p "$FINAL"
    cp -a "$SRC/Game" "$SRC/libpxt.so" "$FINAL/"
    chmod +x "$FINAL/Game"
    # Copy any extra assets the game ships (data files, etc.) alongside the binary.
    find "$SRC" -mindepth 1 -maxdepth 1 ! -name Game ! -name libpxt.so ! -name name.txt ! -name arcade.cfg \
        ! -name '.*' -exec cp -a {} "$FINAL/" \; 2>/dev/null || true

    # Neighboring assets on the stick: a <Game>.png / <Game>-<arch>.png next to
    # the .tar.gz becomes cover.png, <Game>.img becomes cover.img, and
    # <Game>.json becomes info.json for the menu.
    if [ -n "$TARBALL" ]; then
        local TAR_BASE TAR_GAME base
        TAR_BASE="$(basename "$TARBALL" .tar.gz)"
        TAR_GAME="${TAR_BASE%%-arm64}"; TAR_GAME="${TAR_GAME%%-x86-64}"; TAR_GAME="${TAR_GAME%%-win64}"; TAR_GAME="${TAR_GAME%%-amd64}"
        for base in "$TAR_BASE" "$TAR_GAME"; do
            [ -f "$MNT/$base.png" ]  && cp -a "$MNT/$base.png"  "$FINAL/cover.png"  && log "installed cover.png from $base.png"
            [ -f "$MNT/$base.img" ]  && cp -a "$MNT/$base.img"  "$FINAL/cover.img"  && log "installed cover.img from $base.img"
            [ -f "$MNT/$base.json" ] && cp -a "$MNT/$base.json" "$FINAL/info.json"  && log "installed info.json from $base.json"
        done
    fi
    echo "$SRC_MTIME" > "$FINAL/.usb-source-mtime"

    rm -rf "$DEST.old"
    [ -d "$DEST" ] && mv "$DEST" "$DEST.old"
    mv "$FINAL" "$DEST"
    rm -rf "$DEST.old"

    # Other installed games stay put — this is a multi-game cabinet and the
    # menu lists everything under games/.

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
    return 0
}

# Sanity helper used by install_game.
is_elf() {
    [ "$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "7f454c46" ]
}

NEWEST_LAUNCH=""
NEWEST_LAUNCH_MTIME=0

if [ -d "$MNT/arcade-game" ] && [ "$DIR_MTIME" -ge "$TAR_MTIME" ]; then
    mkdir -p "$STAGE/game"
    cp -a "$MNT/arcade-game/." "$STAGE/game/"
    install_game "$STAGE/game" "" "$DIR_MTIME" "" "arcade-game/"
    case $? in 0|2) NEWEST_LAUNCH="$RESULT_NAME"; NEWEST_LAUNCH_MTIME="$DIR_MTIME" ;; esac
elif [ -n "$TARBALL" ]; then
    # Every tarball on the stick gets installed, newest-first. A bad one is
    # skipped and we move to the next. The newest usable one gets launched.
    N=0
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        CAND_MTIME="${cand%% *}"; CAND_MTIME="${CAND_MTIME%%.*}"
        CAND_TAR="${cand#* }"
        CAND_LABEL="$(basename "$CAND_TAR")"
        CAND_NAME="$(basename "$CAND_TAR" .tar.gz | sed -E 's/-(arm64|x86-64|win64|amd64)$//' | tr -cd 'A-Za-z0-9._-')"

        # Validate BEFORE extracting: must list Game + libpxt.so and contain
        # no absolute paths or ../ traversal entries.
        LISTING="$(tar tzf "$CAND_TAR" 2>/dev/null || true)"
        if [ -z "$LISTING" ]; then
            log "found $CAND_LABEL but it is not a readable tar.gz; skipping"
            continue
        fi
        if echo "$LISTING" | grep -qE '^(/|\.\./)|/\.\./'; then
            log "found $CAND_LABEL but it contains unsafe paths (absolute or ../); skipping"
            continue
        fi
        if ! echo "$LISTING" | grep -qE '(^|/)Game$' || ! echo "$LISTING" | grep -qE '(^|/)libpxt\.so$'; then
            log "found $CAND_LABEL but it has no Game + libpxt.so inside; skipping"
            continue
        fi

        N=$((N + 1))
        CAND_STAGE="$STAGE/tar-$N"
        mkdir -p "$CAND_STAGE"
        if ! tar xzf "$CAND_TAR" -C "$CAND_STAGE" 2>/dev/null; then
            log "found $CAND_LABEL but could not extract it; skipping"
            rm -rf "$CAND_STAGE"
            continue
        fi
        # Locate the dir holding Game + libpxt.so (archive may nest them).
        CAND_SRC="$(dirname "$(find "$CAND_STAGE" -name Game -type f | head -n1)" 2>/dev/null)"
        if [ ! -f "$CAND_SRC/Game" ] || [ ! -f "$CAND_SRC/libpxt.so" ]; then
            log "found $CAND_LABEL but Game/libpxt.so not usable; skipping"
            continue
        fi

        install_game "$CAND_SRC" "$CAND_NAME" "$CAND_MTIME" "$CAND_TAR" "$CAND_LABEL"
        rc=$?
        if { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && [ "$CAND_MTIME" -gt "$NEWEST_LAUNCH_MTIME" ]; then
            NEWEST_LAUNCH="$RESULT_NAME"
            NEWEST_LAUNCH_MTIME="$CAND_MTIME"
        fi
    done < <(find "$MNT" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' ! -name '.*' -printf '%T@ %p\n' 2>/dev/null | sort -nr)
fi

if [ -z "$NEWEST_LAUNCH" ]; then
    log "nothing usable on $DEV; ignoring"
    exit 0
fi

# Point the launcher at the newest game: write a launch request. launcher.sh
# reads this file every loop, so killing the running Game (menu or game)
# swaps us straight into the new game without a reboot.
REQUEST_FILE="/tmp/creationstation_launch_request"
echo "$NEWEST_LAUNCH" > "$REQUEST_FILE"
chown "$ARCADE_USER:$ARCADE_USER" "$REQUEST_FILE" 2>/dev/null || true

sync

GAME_PID=""
[ -f /tmp/creationstation_current_game.pid ] && GAME_PID="$(cat /tmp/creationstation_current_game.pid 2>/dev/null || true)"
if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
    log "switching live: killing running Game (pid $GAME_PID); launcher will restart '$NEWEST_LAUNCH'"
    kill "$GAME_PID" 2>/dev/null || true
else
    log "no running Game found; '$NEWEST_LAUNCH' starts on next launch"
fi
log "done; active game is now '$NEWEST_LAUNCH'"
