#!/bin/bash

## Kill the pi processes
sudo pkill -9 -u pi

## Get the latest code
cd /home/pi/CreationStationArcade
git fetch
git reset --hard origin/main

## Reboot the pi
sudo reboot
