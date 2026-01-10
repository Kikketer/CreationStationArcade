
#!/bin/bash
LOG_FILE="/home/pi/mcairpos.log"

# Self-update logic
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Checking for updates..." >> $LOG_FILE
git fetch origin >> $LOG_FILE 2>&1

if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Update found. Resetting to origin/main..." >> $LOG_FILE
    git reset --hard origin/main >> $LOG_FILE 2>&1
    # Kill background monitor so it can be restarted with new code
    pkill -f "monitor_kill.py"

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restarting launcher..." >> $LOG_FILE
    exec "$SCRIPT_DIR/$(basename "$0")" "$@"
fi

# Start background monitor if not running
if ! pgrep -f "monitor_kill.py" > /dev/null; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting monitor_kill.py..." >> $LOG_FILE
    python3 "$SCRIPT_DIR/monitor_kill.py" >> $LOG_FILE 2>&1 &
fi


while true; do
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Menu" >> $LOG_FILE
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap verbose /home/pi/CreationStationArcade/menu.elf >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Menu exited with status $?" >> $LOG_FILE

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Game" >> $LOG_FILE
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap verbose /home/pi/CreationStationArcade/games/SyncTheBoatSync.elf >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Game exited with status $?" >> $LOG_FILE
done