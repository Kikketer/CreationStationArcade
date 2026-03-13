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
8. Optional: Make the /sd/prj folder if you wish to use a custom menu
   - `sudo mkdir -p /sd/prj`
   - `sudo chmod +w /sd/prj` (cuz I don't care)
   - The custom menu will list and launch games from this folder

9. Set the login for the `pi` user to use the runtime `launcher.sh` instead of bash, this will just force that user to fire up the arcade loop.
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

If you don't need to use all 4 players you can simply export your game as a raw elf from the standard MakeCode Arcade interface. Raw elf is hidden and really crossing my fingers they don't remove this feature, but maybe if you promote my post and github fork we'd be able to get it built in for real! https://forum.makecode.com/t/4-player-gpio-raw-elf-export/41383

1. Put `?nolocalhost=1&compile=rawELF&hw=rpi#editor` on the end of the url.
2. Load the game you wish to add to the arcade
3. Click the "download" button on the bottom left
4. You'll then have a `.elf` file downloaded
5. Move this file to the CreationStationArcade/gaems directory
6. Commit and push the repo
7. The arcade will pull and copy over the next time it boots, it'll take two reboots (one to download, and one to copy over).

### 4 Player Option

4 Player games are not officially supported by MakeCode Arcade (even though the "cardboard" setup has the pin layout). So if you need to build a game for the 4 player controllers you need to do it manually and locally.

1. Setup the pxt, pxt-arcade, and pxt-common-packages repos from my forks (this is a little painful but you got this). I put everything in a single folder called `pxt-root`.
   - https://github.com/Kikketer/pxt/tree/kikketer/feat-raw-elf-four-player
   - https://github.com/Kikketer/pxt-arcade/tree/kikketer/feat-raw-elf-four-player
   - https://github.com/Kikketer/pxt-common-packages/tree/master
2. There's an npm link step here... trying to remember how to do it, it was finicky at best
3. Once you have all the repos checked into that single `pxt-root` folder be sure to check out the "feat-raw-elf-four-player" branches of the pxt and pxt-arcade projects.
4. Navigate to `pxt-arcade` and run `npm serve`
5. A local copy will start, now you just need to import the game you wish to put on the arcade.
6. Once you have the game loaded, pick the "choose hardware" near the download button
7. Pick "Pi0 Raw Elf" option
8. Click download
9. Now you have a 4 player .elf file that can be used on the arcade, copy this into the `CreationStationArcade/games` folder
10. Update the `launcher.sh` to point to your new game name
11. Commit and push
12. Then reboot the arcade box, it'll pull on the first reboot, reboot again and it'll copy over the new one (yes that's 2 reboots)

## Known Issues

- Raspberry PI 3 is the only modern device that works due to "Hardweare" line needed in the `/proc/cpuinfo` which is generally useless but the ELF files demand it to be there.

> The Pi 3 works because it still ships a slightly older 6.x kernel point-release that still contains the “Hardware” line.
> The Pi 5 image you flashed already carries a newer 6.x point-release in which the Raspberry Pi Foundation deliberately deleted that line (they got tired of every Pi reporting BCM2835 and confusing users).
> So on the Pi 5 the ELF aborts, while on the Pi 3 it starts—even though both run the same 32-bit Trixie Lite OS.
> Once your Pi 3 updates to the same kernel revision as the Pi 5, it will also lose the line and fail in exactly the same way.

BTW that sounds like a horrible day, so let's get a copy of that OS and keep it forever.

- `wiringPi` is dead on Raspberry Pi 5

This means that the GPIO is basically useless and can't be used for the gaming machine.
