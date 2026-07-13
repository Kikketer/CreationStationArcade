#!/bin/bash
# launch-4player.sh

ELF_NAME=$(basename "$1" .elf)
ELF_PATH="$1"

PIDFILE="/tmp/creationstation_current_elf.pid"

SELF_PID=$$
PARENT_PID=$PPID

if [ -z "$ELF_PATH" ]; then
    echo "Usage: $0 /full/path/to/game.elf"
    exit 2
fi

if [ ! -x "$ELF_PATH" ]; then
    echo "ERROR: ELF not found or not executable: $ELF_PATH"
    exit 2
fi

find_running_pid() {
    local pid
    pid=$(pgrep -f "$ELF_PATH" 2>/dev/null | grep -v -E "^(${SELF_PID}|${PARENT_PID})$" | tail -n 1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi

    pid=$(pgrep "$ELF_NAME" 2>/dev/null | grep -v -E "^(${SELF_PID}|${PARENT_PID})$" | tail -n 1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi

    return 1
}

write_pidfile() {
    local pid="$1"
    if [ -n "$pid" ]; then
        echo "$pid" > "$PIDFILE"
    fi
}

# Launch the game

"$ELF_PATH" &
LAUNCH_PID=$!

# Give it a moment to spawn the real process
sleep 2

# Track the actual running process (by full path if possible)
PID=$(find_running_pid)
if [ -z "$PID" ]; then
    PID="$LAUNCH_PID"
fi
write_pidfile "$PID"

MISSING_COUNT=0
while true; do
    if kill -0 "$PID" 2>/dev/null && ! grep -q "^State:.*Z" /proc/"$PID"/status 2>/dev/null; then
        MISSING_COUNT=0
    else
        NEW_PID=$(find_running_pid || true)
        if [ -n "$NEW_PID" ]; then
            PID="$NEW_PID"
            write_pidfile "$PID"
            MISSING_COUNT=0
        else
            MISSING_COUNT=$((MISSING_COUNT + 1))
            if [ "$MISSING_COUNT" -ge 2 ]; then
                echo "Game exited."
                break
            fi
        fi
    fi
    sleep 2
done

# Cleanup
fbset -depth 8 && fbset -depth 16
echo "Framebuffer restored."

# Show splash image to cover TTY text during restart
SPLASH_RAW="$(dirname "$0")/splash.raw"
SPLASH="$(dirname "$0")/splash.png"
if [ -f "$SPLASH_RAW" ]; then
    # Pre-converted RGB565 raw — instant, no Python needed
    cat "$SPLASH_RAW" > /dev/fb0 2>/dev/null &
elif [ -f "$SPLASH" ]; then
    python3 - "$SPLASH" <<'PYEOF' &
import sys, zlib, struct
def read_png(path):
    with open(path, 'rb') as f:
        raw_file = f.read()
    # Find IHDR by scanning (skips any BOM/header issues)
    idx = raw_file.find(b'IHDR')
    if idx < 0:
        return None, 0, 0
    f = __import__('io').BytesIO(raw_file[idx - 4:])
    chunks = {}
    while True:
        hdr = f.read(8)
        if len(hdr) < 8:
            break
        length = struct.unpack('>I', hdr[:4])[0]
        ctype = hdr[4:]
        data = f.read(length)
        f.read(4)  # crc
        chunks.setdefault(ctype, b'')
        chunks[ctype] += data
        if ctype == b'IEND':
            break
    ihdr = chunks[b'IHDR']
    w, h = struct.unpack('>II', ihdr[:8])
    ct = ihdr[9]
    # ct=2 RGB, ct=3 palette, ct=6 RGBA
    palette = None
    if ct == 3:
        pal_data = chunks.get(b'PLTE', b'')
        palette = [pal_data[i*3:(i+1)*3] for i in range(len(pal_data)//3)]
        bpp = 1
    else:
        bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(chunks[b'IDAT'])
    stride = w * bpp + 1
    pixels = bytearray(w * h * 3)
    prev = bytearray(w * bpp)
    for y in range(h):
        row = bytearray(raw[y * stride + 1: (y + 1) * stride])
        ft = raw[y * stride]
        if ft == 1:
            for x in range(bpp, len(row)):
                row[x] = (row[x] + row[x - bpp]) & 0xFF
        elif ft == 2:
            for x in range(len(row)):
                row[x] = (row[x] + prev[x]) & 0xFF
        elif ft == 3:
            for x in range(len(row)):
                a = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + (a + prev[x]) // 2) & 0xFF
        elif ft == 4:
            for x in range(len(row)):
                a = row[x - bpp] if x >= bpp else 0
                b2 = prev[x]; c = prev[x - bpp] if x >= bpp else 0
                p = a + b2 - c
                pa, pb, pc = abs(p-a), abs(p-b2), abs(p-c)
                pr = a if pa <= pb and pa <= pc else (b2 if pb <= pc else c)
                row[x] = (row[x] + pr) & 0xFF
        prev = row
        for x in range(w):
            if palette:
                rgb = palette[row[x]]
                pixels[(y * w + x) * 3:(y * w + x) * 3 + 3] = rgb
            else:
                o = x * bpp
                pixels[(y * w + x) * 3:(y * w + x) * 3 + 3] = row[o:o+3]
    return pixels, w, h
try:
    pixels, img_w, img_h = read_png(sys.argv[1])
    if pixels is None:
        sys.exit(0)
    fb_w, fb_h = 1280, 1024
    x_off = (fb_w - img_w) // 2
    y_off = (fb_h - img_h) // 2
    # Build full framebuffer as black then blit image rows
    fb = bytearray(fb_w * fb_h * 2)
    for y in range(img_h):
        base = y * img_w * 3
        row_rgb = pixels[base:base + img_w * 3]
        # Bulk convert row to RGB565 little-endian
        row565 = bytearray(img_w * 2)
        for x in range(img_w):
            r = row_rgb[x*3]; g = row_rgb[x*3+1]; b = row_rgb[x*3+2]
            px = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            row565[x*2] = px & 0xFF
            row565[x*2+1] = (px >> 8) & 0xFF
        fb_row_start = ((y + y_off) * fb_w + x_off) * 2
        fb[fb_row_start:fb_row_start + img_w * 2] = row565
    with open('/dev/fb0', 'wb') as f:
        f.write(bytes(fb))
except Exception:
    pass
PYEOF
fi  # end elif splash.png
fi  # end if splash.raw

rm -f "$PIDFILE" 2>/dev/null || true

# To kill the game: pkill -f launch-4player.sh