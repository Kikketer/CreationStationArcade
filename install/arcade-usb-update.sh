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
# Per-invocation mountpoint: each partition of a drive fires its own
# service instance, and a shared mountpoint lets one partition's mount
# shadow another's (scans then read the wrong filesystem).
MNT=$(mktemp -d /mnt/arcade-usb.XXXXXX)
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
    MNT_RW=1
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
        rmdir "$MNT" 2>/dev/null || true
        rm -rf "$STAGE"
    }
    trap cleanup EXIT

    # The filesystem may need a moment to settle after the udev add event.
    # Mount read-write so the config sync can write the merged config back
    # to the stick; fall back to read-only (install still works, no write-back).
    MOUNTED=0
    MNT_RW=0
    for _ in 1 2 3 4 5; do
        if mount -o rw "$DEV" "$MNT" 2>/dev/null; then
            MOUNTED=1
            MNT_RW=1
            break
        elif mount -o ro "$DEV" "$MNT" 2>/dev/null; then
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
        if f.startswith('.') or f in ('config.json', 'config.jsonc'):
            continue
        if os.path.isfile(os.path.join(arcade_dir, f)):
            add(arcade_dir, f)

for fname in sorted(best):
    print(f"{best[fname]}|{fname}")
PYEOF

HAS_CFG=0
for c in "$MNT/arcade-games/config.jsonc" "$MNT/arcade-games/config.json" "$MNT/config.jsonc" "$MNT/config.json"; do
    [ -f "$c" ] && HAS_CFG=1 && break
done

if [ ! -s "$BEST" ] && [ "$HAS_CFG" != "1" ]; then
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

# --- Config round-trip ---
# Merge the stick's config over the box's (per-key; stick wins where set),
# then write the result back to the stick so the drive always shows the
# live config — edit it on any machine and re-dock. Skip entirely when the
# stick carried nothing config-shaped and nothing was installed.
if [ "${MNT_RW:-0}" = "1" ] && { [ "$CHANGED" = "1" ] || [ -d "$MNT/arcade-games" ] || [ -f "$MNT/config.jsonc" ] || [ -f "$MNT/config.json" ]; }; then
python3 - "$MNT" "$GAMES_DIR" <<'PYEOF'
import json, os, re, sys

mnt, gdir = sys.argv[1], sys.argv[2]

def strip_comments(t):
    out, i, ins = [], 0, False
    while i < len(t):
        c, n = t[i], t[i+1] if i+1 < len(t) else ''
        if ins:
            out.append(c)
            if c == '\\' and n: out.append(n); i += 1
            elif c == '"': ins = False
        elif c == '"': ins = True; out.append(c)
        elif c == '/' and n == '/':
            while i < len(t) and t[i] != '\n': i += 1
            continue
        elif c == '/' and n == '*':
            i += 2
            while i < len(t) and not (t[i] == '*' and i+1 < len(t) and t[i+1] == '/'): i += 1
            i += 1
        else: out.append(c)
        i += 1
    return ''.join(out)

def read_cfg(path):
    try:
        return json.loads(strip_comments(open(path).read()))
    except Exception:
        return None

stick_cfg = None
for cand in ('arcade-games/config.jsonc', 'arcade-games/config.json',
             'config.jsonc', 'config.json'):
    p = os.path.join(mnt, cand)
    if os.path.isfile(p):
        stick_cfg = read_cfg(p)
        break

box_cfg = None
box_path = os.path.join(gdir, 'config.jsonc')
for cand in (box_path, os.path.join(gdir, 'config.json')):
    if os.path.isfile(cand):
        box_cfg = read_cfg(cand)
        break

def merge(base, over):
    out = dict(base or {})
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = v
    return out

dst_dir = os.path.join(mnt, 'arcade-games')
if stick_cfg is not None:
    merged = merge(box_cfg, stick_cfg)
    header = '// Merged config — last synced from USB. Stick values override;\n// everything else is reflected back from the machine.\n'
    for dst in (os.path.join(dst_dir, 'config.jsonc'), box_path):
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'w') as f: f.write(header + json.dumps(merged, indent=2) + '\n')
        except Exception:
            pass
    print('config: merged stick over box; wrote merged config.jsonc to both', file=sys.stderr)
elif box_cfg is not None:
    # No config on the stick: mirror the box's current file verbatim so the
    # drive becomes an editable snapshot for the next dock.
    try:
        src = box_path if os.path.isfile(box_path) else os.path.join(gdir, 'config.json')
        os.makedirs(dst_dir, exist_ok=True)
        with open(src) as fi, open(os.path.join(dst_dir, 'config.jsonc'), 'w') as fo:
            fo.write(fi.read())
        print('config: mirrored box config to stick', file=sys.stderr)
    except Exception:
        pass
PYEOF
    chown -R "$ARCADE_USER:$ARCADE_USER" "$GAMES_DIR" 2>/dev/null || true
    log "config sync done"
fi

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
