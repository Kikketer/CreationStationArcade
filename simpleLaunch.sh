#!/bin/bash
# launch-4player.sh

ELF_NAME=$(basename "$1" .elf)
ELF_PATH="$1"

# Launch the game
"$ELF_PATH" &

# Give it a moment to spawn the real process
sleep 2

# Track the actual running process by name
while true; do
    PID=$(pgrep -n "$ELF_NAME")
    if [ -z "$PID" ]; then
        echo "Game exited."
        break
    fi
    sleep 2
done

# Cleanup
fbset -depth 8 && fbset -depth 16
echo "Framebuffer restored."

# To kill the game: pkill -f launch-4player.sh