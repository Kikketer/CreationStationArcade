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

# Show splash image to cover TTY text during restart (no deps, pure stdlib)
SPLASH="$(dirname "$0")/splash.png"
if [ -f "$SPLASH" ]; then
    python3 - "$SPLASH" <<'PYEOF' &
import sys, zlib, struct
def read_png(path):
    with open(path, 'rb') as f:
        sig = f.read(8)
        if sig != b'\x89PNG\r\n\x1a\n':
            return None, 0, 0
        chunks = {}
        while True:
            length = struct.unpack('>I', f.read(4))[0]
            ctype = f.read(4)
            data = f.read(length)
            f.read(4)  # crc
            chunks.setdefault(ctype, b'')
            chunks[ctype] += data
            if ctype == b'IEND':
                break
        w, h, bd, ct = struct.unpack('>IIBBBBB', chunks[b'IHDR'])[:4]
        raw = zlib.decompress(chunks[b'IDAT'])
        bpp = 3 if ct == 2 else 4 if ct == 6 else 1
        stride = w * bpp + 1
        pixels = bytearray(w * h * 3)
        for y in range(h):
            row = raw[y * stride: y * stride + stride]
            ft = row[0]
            for x in range(w):
                o = x * bpp
                r = row[1 + o]; g = row[2 + o]; b = row[3 + o]
                pixels[(y * w + x) * 3:] = bytes([r, g, b])
        return pixels, w, h
try:
    pixels, img_w, img_h = read_png(sys.argv[1])
    if pixels is None:
        sys.exit(0)
    fb_w, fb_h = 1280, 1024
    fb = bytearray(fb_w * fb_h * 2)
    x_off = (fb_w - img_w) // 2
    y_off = (fb_h - img_h) // 2
    for y in range(img_h):
        for x in range(img_w):
            base = (y * img_w + x) * 3
            r, g, b = pixels[base], pixels[base+1], pixels[base+2]
            px = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            idx = ((y + y_off) * fb_w + (x + x_off)) * 2
            if 0 <= idx < len(fb) - 1:
                fb[idx] = px & 0xFF
                fb[idx+1] = (px >> 8) & 0xFF
    with open('/dev/fb0', 'wb') as f:
        f.write(bytes(fb))
except Exception:
    pass
PYEOF
fi

rm -f "$PIDFILE" 2>/dev/null || true

# To kill the game: pkill -f launch-4player.sh