
#!/bin/bash
LOG_FILE="/home/pi/mcairpos.log"

while true; do
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Menu" >> $LOG_FILE
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap verbose /home/pi/CreationStationArcade/menu.elf >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Menu exited with status $?" >> $LOG_FILE

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Launching Game" >> $LOG_FILE
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap verbose /home/pi/CreationStationArcade/games/Robob.elf >> $LOG_FILE 2>&1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Game exited with status $?" >> $LOG_FILE
done