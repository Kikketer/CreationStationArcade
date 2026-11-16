#!/bin/bash
# arcade-usb-update.sh — install a game from a USB stick or floppy disk and
# switch to it (single-game-chromium flavor).
#
# Triggered by arcade-disk-load.sh on reset when a USB floppy holds a new
# game. Runs as root; no user interaction.
#   arcade-usb-update.sh --check <dev>   only reads the drive's file list and
#                                        exits 0 if it holds a game that isn't
#                                        the active one, 1 otherwise
# <dev> may also be an already-mounted directory (handy for testing).
#
# Disk format — any of these:
#   <Name>.js       — output of the PNG to JS compiler; siblings with the same
#                     basename (<Name>.png/.gif/.json) are cover/metadata
#   <Name>.js.gz    — gzip of the same, for media too small for a bare .js
#                     (a 1.44MB floppy fits ~3MB of compiled game gzipped)
#   arcade-games/   — a folder of the above; the newest .js(.gz) inside wins
#
# The newest candidate on the disk wins. Games install into GAMES_DIR — a
# persistent folder OUTSIDE the runtime checkout, which the boot-time
# rsync --delete would wipe. server.js serves GAMES_DIR before the checkout's
# own games/ folder.
#
# /etc/arcade-usb-update.conf (written by the installer) provides:
#   GAMES_DIR    — persistent folder holding installed disk games
#   ARCADE_USER  — user that owns the games and runs the launcher
#   ARCADE_USER_HOME — optional, defaults to the user's real home
#
# Freshness: GAMES_DIR/.active-game names the running game, and
# .active-source-id/.active-source-mtime record what it was installed from.
# A disk is "the same" when its candidate's source id (name:size:mtime)
# matches, or by the old same-name-and-not-newer rule — stops a left-in disk
# from reinstalling on every reset.

set -u

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
    shift
fi
DEV="${1:-}"
CONF="${ARCADE_USB_CONF:-/etc/arcade-usb-update.conf}"
GAMES_DIR=""
ARCADE_USER="pi"
ARCADE_USER_HOME=""
[ -f "$CONF" ] && . "$CONF"
ARCADE_USER_HOME="${ARCADE_USER_HOME:-$(getent passwd "$ARCADE_USER" 2>/dev/null | cut -d: -f6)}"
[ -n "$ARCADE_USER_HOME" ] || ARCADE_USER_HOME="/home/$ARCADE_USER"
[ -n "$GAMES_DIR" ] || GAMES_DIR="$ARCADE_USER_HOME/arcade-games"

LOG_FILE="${ARCADE_LOG:-$ARCADE_USER_HOME/arcade.log}"
MNT=/mnt/arcade-usb
MOUNT_TRIES="${ARCADE_MOUNT_TRIES:-5}"
LOCK_FILE="${ARCADE_LOCK_FILE:-/run/arcade-game-update.lock}"
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
    echo "Usage: $0 [--check] <block-device|directory>" >&2
    exit 2
fi

mkdir -p "$GAMES_DIR" || fail "could not create $GAMES_DIR"

# One update at a time.
if touch "$LOCK_FILE" 2>/dev/null; then
    exec 9>>"$LOCK_FILE"
    flock -w 300 9 || log "WARNING: timed out waiting for $LOCK_FILE; continuing"
fi

# In --check mode "nothing to do" exits 1; a normal run just ignores it.
nothing_to_do() {
    log "$*"
    [ "$CHECK_ONLY" = "1" ] && exit 1
    exit 0
}

log "checking $DEV for an arcade game"

MOUNTED=0
if [ -d "$DEV" ]; then
    MNT="$DEV"
else
    mkdir -p "$MNT"
    # The filesystem may need a moment to settle after the udev add event.
    for _ in $(seq "$MOUNT_TRIES"); do
        if mount -o ro "$DEV" "$MNT" 2>/dev/null; then
            MOUNTED=1
            break
        fi
        sleep 1
    done
fi

cleanup() {
    [ "$MOUNTED" = "1" ] && umount "$MNT" 2>/dev/null
    rm -rf "$STAGE"
}
trap cleanup EXIT

if [ "$MOUNTED" != "1" ] && [ ! -d "$DEV" ]; then
    nothing_to_do "could not mount $DEV; ignoring"
fi

# --- Find the candidate: the newest .js or .js.gz on the disk ---
# Root files and arcade-games/ files compete on mtime; sidecars with the same
# basename travel with the .js.
CAND=""
CAND_MTIME=0
NEWEST="$( { find "$MNT" -mindepth 1 -maxdepth 1 -type f \( -name '*.js' -o -name '*.js.gz' \) ! -name '.*' -printf '%T@ %p\n' 2>/dev/null;
           find "$MNT/arcade-games" -mindepth 1 -maxdepth 1 -type f \( -name '*.js' -o -name '*.js.gz' \) ! -name '.*' -printf '%T@ %p\n' 2>/dev/null; } | sort -nr | head -n1 )"
if [ -n "$NEWEST" ]; then
    CAND_MTIME="${NEWEST%% *}"
    CAND="${NEWEST#* }"
fi

if [ -z "$CAND" ]; then
    nothing_to_do "no .js game on $DEV; ignoring"
fi
CAND_MTIME="${CAND_MTIME%%.*}"

# Game name from the file: strip .gz then .js, then any -arch suffix.
game_name() {
    local n
    n="$(basename "$1")"
    n="${n%.gz}"
    n="${n%.js}"
    echo "$n" | sed -E 's/-(arm64|x86-64|win64|amd64)$//' | tr -cd 'A-Za-z0-9._-'
}
GAME_NAME="$(game_name "$CAND")"
[ -n "$GAME_NAME" ] || GAME_NAME="DiskGame"

# The game file itself and its sidecars (same basename, any of png/gif/json)
# live next to it in the same directory.
CAND_BASE="${CAND%.gz}"
CAND_BASE="${CAND_BASE%.js}"
CAND_DIR="$(dirname "$CAND")"

# Identifies a source without reading its contents, so a slow floppy only has
# to read its directory to tell whether the game changed.
SOURCE_ID="$(basename "$CAND"):$(stat -c %s "$CAND"):$(stat -c %Y "$CAND")"

ACTIVE_FILE="$GAMES_DIR/.active-game"
CURRENT_ACTIVE=""
[ -f "$ACTIVE_FILE" ] && CURRENT_ACTIVE="$(head -n1 "$ACTIVE_FILE" | tr -cd 'A-Za-z0-9._-')"
# Machines configured before .active-game existed carry the name in the env.
if [ -z "$CURRENT_ACTIVE" ]; then
    CURRENT_ACTIVE="$(grep -oE 'SINGLE_GAME_NAME="[^"]*"' "$ARCADE_USER_HOME/.xinitrc" 2>/dev/null | head -n1 | cut -d'"' -f2)"
fi

# game_is_current: true only when the disk's game IS the active one and was
# installed from this exact source, or the disk copy isn't newer. The name
# must match first: a stale .active-source-id left over from before a
# re-setup must not block switching back to that cartridge.
game_is_current() {
    [ "$CURRENT_ACTIVE" = "$GAME_NAME" ] || return 1
    [ "$(cat "$GAMES_DIR/.active-source-id" 2>/dev/null)" = "$SOURCE_ID" ] && return 0
    local installed=0
    [ -f "$GAMES_DIR/.active-source-mtime" ] && installed="$(cat "$GAMES_DIR/.active-source-mtime" 2>/dev/null || echo 0)"
    [ "$CAND_MTIME" -le "${installed:-0}" ]
}

if game_is_current; then
    nothing_to_do "$(basename "$CAND") on $DEV is already the active game '$CURRENT_ACTIVE'"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    log "$DEV has a new game: $(basename "$CAND")"
    exit 0
fi

log "found game source: $(basename "$CAND") -> '$GAME_NAME'"

# --- Stage and validate ---
mkdir -p "$STAGE/game"
GAME_OUT="$STAGE/game/$GAME_NAME.js"
case "$CAND" in
    *.js.gz)
        gzip -t "$CAND" 2>/dev/null || { log "$(basename "$CAND") is not a readable .gz; ignoring"; exit 0; }
        gunzip -c "$CAND" > "$GAME_OUT" || { log "could not decompress $(basename "$CAND"); ignoring"; exit 0; }
        ;;
    *.js)
        cp "$CAND" "$GAME_OUT"
        ;;
esac

# Sanity: a compiled MakeCode game is a big JS file with pxsim code inside —
# an HTML error page or a stray text file fails here.
if [ "$(stat -c %s "$GAME_OUT" 2>/dev/null || echo 0)" -lt 10240 ] || ! grep -m1 -qE 'pxsim|ectx' "$GAME_OUT"; then
    log "$(basename "$CAND") does not look like a compiled MakeCode game; ignoring"
    exit 0
fi

find "$CAND_DIR" -mindepth 1 -maxdepth 1 -type f \
    \( -name "$(basename "$CAND_BASE").png" -o -name "$(basename "$CAND_BASE").gif" -o -name "$(basename "$CAND_BASE").json" \) \
    -exec cp {} "$STAGE/game/" \; 2>/dev/null || true

# Install into the persistent games dir, then point the launcher at it.
# On a failed copy (e.g. full filesystem) drop any partial files and bail
# BEFORE writing freshness markers — otherwise a truncated game would be
# marked active and the source-id would suppress retries.
if ! cp -a "$STAGE/game/." "$GAMES_DIR/"; then
    rm -f "$GAMES_DIR/$GAME_NAME.js"
    for ext in png gif json; do rm -f "$GAMES_DIR/$(basename "$CAND_BASE").$ext"; done
    fail "copy into $GAMES_DIR failed; previous game kept, retry not suppressed"
fi
rm -f "$GAMES_DIR/$GAME_NAME.js.gz"   # never leave the packed form behind
echo "$CAND_MTIME" > "$GAMES_DIR/.active-source-mtime"
echo "$SOURCE_ID" > "$GAMES_DIR/.active-source-id"
echo "$GAME_NAME" > "$ACTIVE_FILE"
chown -R "$ARCADE_USER:$ARCADE_USER" "$GAMES_DIR" 2>/dev/null || true

sync
log "installed '$GAME_NAME' into $GAMES_DIR; it is now the active game"
