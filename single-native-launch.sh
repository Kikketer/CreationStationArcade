#!/bin/bash
# single-native-launch.sh — launch one native MakeCode Arcade Game binary

GAME_DIR="$1"
PIDFILE="/tmp/creationstation_current_game.pid"

if [ -z "$GAME_DIR" ]; then
    echo "Usage: $0 <game-directory>" >&2
    exit 2
fi

if [ ! -d "$GAME_DIR" ]; then
    echo "ERROR: game directory not found: $GAME_DIR" >&2
    exit 1
fi

cd "$GAME_DIR" || exit 1

if [ ! -x ./Game ]; then
    echo "ERROR: ./Game not found or not executable in $GAME_DIR" >&2
    exit 1
fi

if [ ! -f ./libpxt.so ]; then
    echo "ERROR: ./libpxt.so not found in $GAME_DIR" >&2
    exit 1
fi

# Ensure Game can resolve libpxt.so in its own directory.
export LD_LIBRARY_PATH="$GAME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

./Game -f &
PID=$!
echo "$PID" > "$PIDFILE"

# Capture the exit status manually so we can clean up the PID file.
STATUS=0
wait "$PID" || STATUS=$?

rm -f "$PIDFILE"
exit "$STATUS"
