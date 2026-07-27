#!/bin/bash
# single-native-launch.sh — launch one native MakeCode Arcade Game binary

GAME_FILE="$1"
PIDFILE="/tmp/creationstation_current_game.pid"

if [ -z "$GAME_FILE" ]; then
    echo "Usage: $0 <game-file>" >&2
    exit 2
fi

if [ ! -f "$GAME_FILE" ] || [ ! -x "$GAME_FILE" ]; then
    echo "ERROR: game file not found or not executable: $GAME_FILE" >&2
    exit 1
fi

GAME_DIR="$(dirname "$GAME_FILE")"
GAME_NAME="$(basename "$GAME_FILE")"

cd "$GAME_DIR" || exit 1

# Ensure Game can resolve libpxt.so in the same directory.
export LD_LIBRARY_PATH="$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"./$GAME_NAME" -f &
PID=$!
echo "$PID" > "$PIDFILE"

# Capture the exit status manually so we can clean up the PID file.
STATUS=0
wait "$PID" || STATUS=$?

rm -f "$PIDFILE"
exit "$STATUS"
