#!/bin/bash
# arcade-usb-update.sh — install games from a USB stick (chromium-kiosk flavor).
# Triggered by the arcade-usb-update@.service systemd unit via udev when a
# USB filesystem is inserted. Runs as root; no user interaction.
#
# USB format — either layout works:
#   *.js at the drive root — each <Name>.js is a game; siblings with the same
#       basename (<Name>.png, <Name>.gif, <Name>.json) are its cover art and
#       metadata. Root files without a matching .js are ignored.
#   arcade-games/ — every file directly inside is installed as-is (games,
#       covers, games.json, metadata sidecars). Drop a whole games/ folder
#       here to migrate a cabinet in one shot.
#
# A <Name>.json sidecar or a games.json entry can set per-game metadata:
#   {"name": "...", "author": "...", "playerCount": 2, "image": "..."}
#
# Games are copied into GAMES_DIR (outside the git checkout and the runtime
# folder, so they survive the boot-time git reset + rsync wipe). server.js
# serves GAMES_DIR/games.json via /api/games and the running menu picks up
# changes within a few seconds — no reboot needed.
#
# /etc/arcade-usb-update.conf (written by the installer) provides:
#   GAMES_DIR    — persistent folder holding all installed games
#   ARCADE_USER  — user that owns the games and runs the launcher
#
# Freshness: each installed file gets a stamp in .usb-source-mtimes recording
# the mtime seen on the stick. Files that aren't newer than what's installed
# are skipped — stops the reinstall-churn when a stick is left inserted.
#
# Testing: set CSA_USB_TEST_DIR to a folder to treat it as the USB drive
# (skips mounting) — handy for dry runs.

set -u

DEV="${1:-}"
CONF="${ARCADE_USB_CONF:-/etc/arcade-usb-update.conf}"
GAMES_DIR=""
ARCADE_USER="pi"
[ -f "$CONF" ] && . "$CONF"

ARCADE_USER_HOME="$(getent passwd "$ARCADE_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$ARCADE_USER_HOME" ] || ARCADE_USER_HOME="/home/$ARCADE_USER"
[ -n "$GAMES_DIR" ] || GAMES_DIR="$ARCADE_USER_HOME/arcade-games"

LOG_FILE="${ARCADE_LOG:-$ARCADE_USER_HOME/arcade.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
MNT=/mnt/arcade-usb
STAGE="$(mktemp -d)"
MTIMES="$GAMES_DIR/.usb-source-mtimes"
META_FILE="$GAMES_DIR/usb-meta.json"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] usb-update: $*"
    ( echo "[$(date +'%Y-%m-%d %H:%M:%S')] usb-update: $*" >> "$LOG_FILE" ) 2>/dev/null || true
}

mkdir -p "$GAMES_DIR"

if [ -n "${CSA_USB_TEST_DIR:-}" ]; then
    MNT="$CSA_USB_TEST_DIR"
    log "test mode: using $MNT as the USB drive"
    trap 'rm -rf "$STAGE"' EXIT
else
    if [ -z "$DEV" ]; then
        echo "Usage: $0 <block-device>" >&2
        exit 2
    fi

    log "checking $DEV for arcade games"
    mkdir -p "$MNT"

    cleanup() {
        umount "$MNT" 2>/dev/null || true
        rm -rf "$STAGE"
    }
    trap cleanup EXIT

    # The filesystem may need a moment to settle after the udev add event.
    MOUNTED=0
    for _ in 1 2 3 4 5; do
        if mount -o ro "$DEV" "$MNT" 2>/dev/null; then
            MOUNTED=1
            break
        fi
        sleep 1
    done

    if [ "$MOUNTED" != "1" ]; then
        log "could not mount $DEV; ignoring"
        exit 0
    fi
fi

# --- Collect files to install ---
# Emits "<src-dir>|<basename>" lines, deduped by basename (arcade-games/ wins
# over drive root on name clashes). Root-level .js games pull their
# same-basename siblings along; everything inside arcade-games/ is installed.
BEST="$STAGE/best"
python3 - "$MNT" > "$BEST" <<'PYEOF'
import os, sys

mnt = sys.argv[1]
best = {}  # basename -> src dir; arcade-games/ wins by being processed last

def add(src_dir, fname):
    best[fname] = src_dir

try:
    root_files = [f for f in os.listdir(mnt)
                  if os.path.isfile(os.path.join(mnt, f)) and not f.startswith('.')]
except OSError:
    root_files = []

for f in sorted(root_files):
    if f.endswith('.js'):
        base = f[:-3]
        for ext in ('js', 'png', 'gif', 'json'):
            if base + '.' + ext in root_files:
                add(mnt, base + '.' + ext)
if 'games.json' in root_files:
    add(mnt, 'games.json')

arcade_dir = os.path.join(mnt, 'arcade-games')
if os.path.isdir(arcade_dir):
    for f in sorted(os.listdir(arcade_dir)):
        if f.startswith('.'):
            continue
        if os.path.isfile(os.path.join(arcade_dir, f)):
            add(arcade_dir, f)

for fname in sorted(best):
    print(f"{best[fname]}|{fname}")
PYEOF

if [ ! -s "$BEST" ]; then
    log "no game files on the drive; ignoring"
    exit 0
fi

# recorded_mtime <dest-basename> — last-seen source mtime, else 0.
recorded_mtime() {
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(int(json.load(f).get(sys.argv[2], 0)))
except Exception:
    print(0)
" "$MTIMES" "$1" 2>/dev/null || echo 0
}

NEW_MTIMES="$STAGE/mtimes.json"
python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f: data = json.load(f)
except Exception: data = {}
with open(sys.argv[2], 'w') as f: json.dump(data, f)
" "$MTIMES" "$NEW_MTIMES"

stamp() {
    python3 -c "
import json, sys
path, key, mtime = sys.argv[1], sys.argv[2], int(float(sys.argv[3]))
with open(path) as f: data = json.load(f)
data[key] = mtime
with open(path, 'w') as f: json.dump(data, f)
" "$NEW_MTIMES" "$1" "$2"
}

# Feed a .json file's fields into usb-meta.json (sidecar or games.json entry).
# Args: json-path, meta-key, allowed top-level entry flag (0 = treat whole file
#        as the sidecar entry; 1 = file is a games.json list).
record_meta() {
    python3 -c "
import json, sys
meta_path, json_path, key, is_list = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == '1'
try:
    with open(json_path) as f: data = json.load(f)
except Exception:
    sys.exit(1)
try:
    with open(meta_path) as f: meta = json.load(f)
except Exception:
    meta = {}
KEYS = ('name', 'author', 'playerCount', 'image')
if is_list:
    if not isinstance(data, list): sys.exit(1)
    for entry in data:
        if isinstance(entry, dict) and entry.get('file'):
            meta[entry['file']] = {k: entry[k] for k in KEYS if k in entry}
else:
    if not isinstance(data, dict): sys.exit(1)
    meta[key] = {k: data[k] for k in KEYS if k in data}
with open(meta_path, 'w') as f: json.dump(meta, f, indent=2)
" "$META_FILE" "$1" "$2" "$3"
}

CHANGED=0

while IFS='|' read -r SRC_DIR FNAME; do
    [ -n "$FNAME" ] || continue
    SRC="$SRC_DIR/$FNAME"
    SRC_MTIME="$(python3 -c "import os,sys;print(int(os.path.getmtime(sys.argv[1])))" "$SRC" 2>/dev/null || echo 0)"
    DEST="$GAMES_DIR/$FNAME"
    BASE="${FNAME%.json}"; BASE="${BASE%.*}"

    # Metadata feeds: update usb-meta.json instead of (or as well as) copying.
    IS_META=0
    case "$FNAME" in
        games.json) IS_META=2 ;;
        *.json)
            # A sidecar only counts as metadata if a matching .js exists on
            # the stick or is already installed.
            if [ -f "$SRC_DIR/$BASE.js" ] || [ -f "$GAMES_DIR/$BASE.js" ]; then
                IS_META=1
            fi
            ;;
    esac

    if [ "$SRC_MTIME" -le "$(recorded_mtime "$FNAME")" ] && [ -f "$DEST" -o "$IS_META" != "0" ]; then
        continue
    fi

    if [ "$IS_META" = "1" ]; then
        if record_meta "$SRC" "$BASE.js" 0; then
            log "recorded metadata overrides for '$BASE'"
            CHANGED=1
        else
            log "WARNING: $FNAME is not valid JSON; ignoring"
        fi
    elif [ "$IS_META" = "2" ]; then
        # A stick games.json is both the list AND a meta source.
        cp -a "$SRC" "$DEST" || { log "ERROR: could not copy $FNAME"; continue; }
        record_meta "$SRC" "" 1 || true
        log "installed games.json ($(python3 -c "import json;print(len(json.load(open('$DEST'))))" 2>/dev/null || echo '?') entries)"
        CHANGED=1
    else
        cp -a "$SRC" "$DEST" || { log "ERROR: could not copy $FNAME"; continue; }
        log "installed $FNAME"
        CHANGED=1
    fi
    stamp "$FNAME" "$SRC_MTIME"
done < "$BEST"

cp -a "$NEW_MTIMES" "$MTIMES" 2>/dev/null || true

if [ "$CHANGED" != "1" ]; then
    log "nothing newer on the drive; ignoring"
    exit 0
fi

# --- Regenerate games.json ---
# arcade-regen-games.py ships alongside this script (install/ in the repo,
# /usr/local/sbin on the box).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! REGEN_OUT="$(python3 "$SCRIPT_DIR/arcade-regen-games.py" "$GAMES_DIR" 2>&1)"; then
    log "WARNING: games.json regeneration failed: $REGEN_OUT"
else
    log "$REGEN_OUT"
fi

chown -R "$ARCADE_USER:$ARCADE_USER" "$GAMES_DIR" 2>/dev/null || true
sync
log "done; games updated in $GAMES_DIR"
