# Creation Station Arcade

**Full setup docs:** <https://kikketer.github.io/CreationStationArcade> — step-by-step guides for every arcade flavor, written for a non-technical reader.

## Branches

This repo uses long-lived branches to represent different arcade machine configurations.

- `main` — the primary "elf + arcade" setup. The menu itself is an ELF file (`MadeArcadeMenu.elf`) and all games are launched from it. This is the closest to what MakeCode intended for the ELF arcades. Using the [4-player raw ELF compiler](https://www.makecode.games/compilers/elf) you can even use 4 players with GPIO pins.

- `pi3-elf-kiosk` — single-game raw ELF kiosk for Raspberry Pi 3 / Pi Zero. No menu; boots straight into one configured `.elf` game. A USB gamepad is translated to a virtual keyboard (default) or can drive GPIO pins with `--input-mode=gpio` for games built with the [ELF compiler](https://www.makecode.games/compilers/elf).

- `chromium-kiosk` — browser-based arcade for higher-end machines (Raspberry Pi 5 or regular x86 computers). A Node server serves a menu; games run in a separate fullscreen Chromium window, giving you the full MakeCode Arcade extension support you see in the simulator. Supports multiple games with a menu.

- `single-game-kiosk` — the Chromium kiosk but for a single game. Boots directly into one game and the reset button restarts it. Same 1:1 simulator capability as `chromium-kiosk`, but needs a more powerful machine.

- `single-native-arcade` — native SDL MakeCode Arcade `Game` binary running as a single game. No menu, no Chromium; uses direct SDL joystick input, and USB joysticks/buttons are tested. Works on 64-bit ARM (Pi 3/4/5, Pi Zero 2 W) and x86-64 Linux.

- `multi-native-arcade` — not built yet. This will be the native version with a menu system.

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

### Simple Addition

Use the hosted [ELF compiler](https://www.makecode.games/compilers/elf) for every game — it's the 4-player GPIO variety, but it works fine for 1–2 player games too. All the go-forward compilers (desktop, ELF, PNG-to-JS) live at https://www.makecode.games/compilers.

1. Export your game as a PNG from the MakeCode Arcade editor (regular download, the `.png` file is the whole game)
2. Open https://www.makecode.games/compilers/elf and upload that PNG
3. Download the resulting `.elf` file
4. Copy this into the `CreationStationArcade/games` folder
5. Update the `launcher.sh` to point to your new game name
6. Commit and push
7. Then reboot the arcade box, it'll pull on the first reboot, reboot again and it'll copy over the new one (yes that's 2 reboots)

If you want to build it the hard way locally, the forks are still around: `feat-raw-elf-four-player` branches of https://github.com/Kikketer/pxt and https://github.com/Kikketer/pxt-arcade, plus https://github.com/Kikketer/pxt-common-packages. But honestly just use the compiler site.

## Known Issues

- Raspberry PI 3 is the only modern device that works due to "Hardweare" line needed in the `/proc/cpuinfo` which is generally useless but the ELF files demand it to be there.

> The Pi 3 works because it still ships a slightly older 6.x kernel point-release that still contains the “Hardware” line.
> The Pi 5 image you flashed already carries a newer 6.x point-release in which the Raspberry Pi Foundation deliberately deleted that line (they got tired of every Pi reporting BCM2835 and confusing users).
> So on the Pi 5 the ELF aborts, while on the Pi 3 it starts—even though both run the same 32-bit Trixie Lite OS.
> Once your Pi 3 updates to the same kernel revision as the Pi 5, it will also lose the line and fail in exactly the same way.

BTW that sounds like a horrible day, so let's get a copy of that OS and keep it forever.

- `wiringPi` is dead on Raspberry Pi 5

This means that the GPIO is basically useless and can't be used for the gaming machine.
