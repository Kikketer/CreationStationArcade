#!/bin/bash
# pack-usb.sh — build an "arcade cartridge": copy a game onto a USB stick
# and sign it so it only works on that physical stick.
#
# Usage:
#   pack-usb.sh <game-dir> <usb-mount-point> [cart-name]
#     <game-dir>        a directory containing Game + libpxt.so
#                       (extract the compiler's .tar.gz first)
#     <usb-mount-point> where the stick is mounted (e.g. /Volumes/CART,
#                       /media/pi/USB, /mnt/usb)
#     [cart-name]       optional name for games/<Name> on the arcade;
#                       defaults to the game-dir's folder name
#
# The signature binds the game to the stick's filesystem UUID — copying the
# arcade-game/ folder to a different stick will fail the arcade's check.

set -e

SRC="${1:-}"
MNT="${2:-}"
CART_NAME="${3:-}"

usage() {
    echo "Usage: $0 <game-dir> <usb-mount-point> [cart-name]" >&2
    exit 2
}

[ -n "$SRC" ] && [ -n "$MNT" ] || usage
[ -d "$SRC" ] || { echo "ERROR: game dir not found: $SRC" >&2; exit 1; }
[ -d "$MNT" ] || { echo "ERROR: USB mount not found: $MNT" >&2; exit 1; }
[ -f "$SRC/Game" ] || { echo "ERROR: $SRC/Game not found" >&2; exit 1; }
[ -f "$SRC/libpxt.so" ] || { echo "ERROR: $SRC/libpxt.so not found" >&2; exit 1; }

[ -n "$CART_NAME" ] || CART_NAME="$(basename "$(cd "$SRC" && pwd)")"
CART_NAME="$(echo "$CART_NAME" | tr -cd 'A-Za-z0-9._-')"
[ -n "$CART_NAME" ] || { echo "ERROR: cart name must contain letters/digits" >&2; exit 1; }

# --- Find the filesystem UUID of the mounted stick (Linux + macOS) ---
fs_uuid() {
    local mnt="$1" dev
    if command -v findmnt >/dev/null 2>&1; then
        dev="$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)"
        [ -n "$dev" ] && blkid -o value -s UUID "$dev" 2>/dev/null && return
    fi
    if command -v blkid >/dev/null 2>&1; then
        dev="$(df -P "$mnt" | awk 'NR==2 {print $1}')"
        case "$dev" in
            /dev/*) blkid -o value -s UUID "$dev" 2>/dev/null && return ;;
        esac
    fi
    if [ "$(uname -s)" = "Darwin" ]; then
        dev="$(df "$mnt" | awk 'NR==2 {print $1}')"
        diskutil info "$dev" 2>/dev/null | awk -F': *' '/Volume UUID|File System UUID/ {print $2; exit}' | tr -d ' '
        return
    fi
    return 1
}

UUID="$(fs_uuid "$MNT")"
[ -n "$UUID" ] || { echo "ERROR: could not determine filesystem UUID for $MNT" >&2; exit 1; }

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# --- Lay down arcade-game/ on the stick ---
DEST="$MNT/arcade-game"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/Game" "$SRC/libpxt.so" "$DEST/"
find "$SRC" -mindepth 1 -maxdepth 1 ! -name Game ! -name libpxt.so ! -name '._*' \
    -exec cp -R {} "$DEST/" \; 2>/dev/null || true
find "$DEST" -name '._*' -delete 2>/dev/null || true  # macOS metadata junk
echo "$CART_NAME" > "$DEST/name.txt"

# --- Sign: sha256("arcade-cart-v1" + uuid + per-file hashes) ---
# Dotfiles are excluded so OS junk (.DS_Store, ._* etc.) can't break a cart.
{
    echo "arcade-cart-v1"
    echo "$UUID"
    find "$DEST" -mindepth 1 -maxdepth 1 -type f ! -name signature.txt ! -name '.*' \
        | LC_ALL=C sort | while read -r f; do
            h="$(sha "$f" | awk '{print $1}')"
            echo "$h  $(basename "$f")"
        done
} | sha | awk '{print $1}' > "$DEST/signature.txt"

sync 2>/dev/null || true

echo "Packed '$CART_NAME' onto $MNT (uuid $UUID)"
echo "Files:"
find "$DEST" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sed 's/^/  /'
echo "Eject the stick and plug it into the arcade."
