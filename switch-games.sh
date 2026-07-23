#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMES_DIR="$SCRIPT_DIR/games"

if [ ! -d "$GAMES_DIR" ]; then
    echo "ERROR: Games directory not found: $GAMES_DIR" >&2
    exit 1
fi

mapfile -t games < <(find "$GAMES_DIR" -maxdepth 1 -type f -name '*.elf' -printf '%f\n' | sed 's/\.elf$//' | sort)

if [ "${#games[@]}" -eq 0 ]; then
    echo "ERROR: No .elf games found in $GAMES_DIR" >&2
    exit 1
fi

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [GameName]" >&2
    exit 2
fi

if [ "$#" -eq 1 ]; then
    GAME_NAME="$1"
    if [ ! -f "$GAMES_DIR/$GAME_NAME.elf" ]; then
        echo "ERROR: games/$GAME_NAME.elf not found." >&2
        exit 2
    fi
else
    echo "Available games:"
    PS3="Select a game to launch on the next reboot: "
    select GAME_NAME in "${games[@]}"; do
        if [ -n "${GAME_NAME:-}" ]; then
            break
        fi
        echo "Enter a number from the list." >&2
    done
fi

for profile in "$HOME/.bash_profile" "$HOME/.profile"; do
    if grep -qF 'exec bash launcher.sh' "$profile" 2>/dev/null; then
        sed -i "s/^    export SINGLE_GAME_NAME=.*/    export SINGLE_GAME_NAME=\"$GAME_NAME\"/" "$profile"
    fi
done

if [ -f /etc/systemd/system/arcade-monitor.service ]; then
    sudo sed -i "s/^Environment=\"SINGLE_GAME_NAME=.*/Environment=\"SINGLE_GAME_NAME=$GAME_NAME\"/" /etc/systemd/system/arcade-monitor.service
    sudo systemctl daemon-reload
    sudo systemctl restart arcade-monitor.service
fi

echo "Selected game: $GAME_NAME"
echo "Reboot to launch it: sudo reboot"
