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
    if kill -0 "$PID" 2>/dev/null; then
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

rm -f "$PIDFILE" 2>/dev/null || true

# To kill the game: pkill -f launch-4player.sh