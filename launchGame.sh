#!/bin/sh

GAME=${1}
echo "Starting $GAME"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/simpleLaunch.sh" "/home/pi/$GAME"
