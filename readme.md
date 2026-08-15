# Creation Station Arcade (Chromium Edition)

How to setup a Raspberry PI 3:

1. Install the 32bit Lite version of the Raspberry PI OS (Trixie was last tested)
2. Install git: `sudo apt install git`
3. Clone this repo into a source folder: `git clone https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src`
4. Run initial setup to create the runtime folder and sync files: `bash /home/pi/CreationStationArcade-src/setup.sh`
5. Install the boot splash screen to hide boot text and show the arcade logo:
   - `sudo /home/pi/CreationStationArcade/install/splash-setup.sh`
   - `sudo reboot`
   - This installs `fbi`, enables the `arcade-splash` systemd service, and patches `/boot/firmware/cmdline.txt` to suppress kernel boot text.
6. (If you have no HDMI audio in games) Install the HDMI audio fix and reboot:
   - `sudo /home/pi/CreationStationArcade/install/hdmi-audio-fix.sh`
   - `sudo reboot`
7. Make another user, this will be the "admin" user for the raspberry pi so you can admin the machine
   - `sudo adduser admin`
   - `sudo usermod -aG sudo admin`
8. Create a group that both these users belong to so we can admin the files equally
   - `sudo groupadd arcadeadmin`
   - `sudo usermod -aG arcadeadmin pi`
   - `sudo usermod -aG arcadeadmin admin`
   - `sudo chgrp -R arcadeadmin /home/pi`
   - `sudo find /home/pi -type d -exec chmod 2770 {} \;`
   - `sudo find /home/pi -type f -exec chmod 660 {} \;`
   - `echo "umask 002" | sudo tee /etc/profile.d/arcadeadmin.sh`
   - `source /etc/profile.d/arcadeadmin.sh`
9. Make the /sd/prj folder if you wish to use a custom menu
   - `sudo mkdir -p /sd/prj`
   - `sudo chmod +w /sd/prj` (cuz I don't care)
   - The custom menu will list and launch games from this folder

10. Set the login for the `pi` user to use the runtime `launcher.sh` instead of bash, this will just force that user to fire up the arcade loop.
    - `sudo usermod -s /home/pi/CreationStationArcade/launcher.sh pi`

## Folder layout

- `/home/pi/CreationStationArcade-src`
  - Source repo (git)
  - Can be updated in the background and is not actively running
- `/home/pi/CreationStationArcade`
  - Runtime folder
  - On boot, `launcher.sh` syncs from `*-src` to this folder and then runs from here

## Putting Games On The Arcade

1. Export your compiled MakeCode Arcade game as a `.js` file.
2. Drop the `.js` file and a matching `.png` image into `games/`.
3. Run `bash games/refresh_games.sh` to regenerate `games.json`, or edit `games.json` manually to set `name`, `author`, and `playerCount`.
4. Commit and push.
5. Reboot the arcade — `launcher.sh` will pull the latest code and sync it to the runtime folder.
