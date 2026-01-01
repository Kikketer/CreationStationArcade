#!/bin/bash
while true; do
    echo "Launching Menu"
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap /home/pi/CreationStationArcade/menu.elf
    echo "Launching Game"
    /home/pi/McAirpos/McAirpos/launCharc/launCharc nomap /home/pi/CreationStationArcade/games/Robob.elf
done
