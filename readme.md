# Creation Station Arcade

How to setup a Raspberry PI 3:

1. Install the 32bit Lite version of the Raspberry PI OS (Trixie was last tested)
2. Install git: `sudo apt install git`
3. Clone this repo into a source folder: `git clone https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src`
4. Run initial setup to create the runtime folder and sync files: `bash /home/pi/CreationStationArcade-src/setup.sh`
5. (If you have no HDMI audio in games) Install the HDMI audio fix and reboot:
   - `sudo /home/pi/CreationStationArcade/install/hdmi-audio-fix.sh`
   - `sudo reboot`
6. Make another user, this will be the "admin" user for the raspberry pi so you can admin the machine
   - `sudo adduser admin`
   - `sudo usermod -aG sudo admin`
7. Create a group that both these users belong to so we can admin the files equally

   - `sudo groupadd arcadeadmin`
   - `sudo usermod -aG arcadeadmin pi`
   - `sudo usermod -aG arcadeadmin admin`
   - `sudo chgrp -R arcadeadmin /home/pi`
   - `sudo find /home/pi -type d -exec chmod 2770 {} \;`
   - `sudo find /home/pi -type f -exec chmod 660 {} \;`
   - `echo "umask 002" | sudo tee /etc/profile.d/arcadeadmin.sh`
   - `source /etc/profile.d/arcadeadmin.sh`

8. Set the login for the `pi` user to use the runtime `launcher.sh` instead of bash, this will just force that user to fire up the arcade loop.

   - `sudo usermod -s /home/pi/CreationStationArcade/launcher.sh pi`

## Folder layout

- `/home/pi/CreationStationArcade-src`
  - Source repo (git)
  - Can be updated in the background and is not actively running
- `/home/pi/CreationStationArcade`
  - Runtime folder
  - On boot, `launcher.sh` syncs from `*-src` to this folder and then runs from here

## Known Issues

- Raspberry PI 3 is the only modern device that works due to "Hardweare" line needed in the `/proc/cpuinfo` which is generally useless but the ELF files demand it to be there.

> The Pi 3 works because it still ships a slightly older 6.x kernel point-release that still contains the “Hardware” line.
> The Pi 5 image you flashed already carries a newer 6.x point-release in which the Raspberry Pi Foundation deliberately deleted that line (they got tired of every Pi reporting BCM2835 and confusing users).
> So on the Pi 5 the ELF aborts, while on the Pi 3 it starts—even though both run the same 32-bit Trixie Lite OS.
> Once your Pi 3 updates to the same kernel revision as the Pi 5, it will also lose the line and fail in exactly the same way.

BTW that sounds like a horrible day, so let's get a copy of that OS and keep it forever.

- `wiringPi` is dead on Raspberry Pi 5

This means that the GPIO is basically useless and can't be used for the gaming machine.
