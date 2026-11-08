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
- `/home/pi/arcade-games`
  - Persistent games folder (`.js` files, cover art, `games.json`)
  - Seeded from `stock-games/` at setup; USB installs land here
  - Survives the runtime sync — the repo never touches it

## Putting Games On The Arcade

All games live in `/home/pi/arcade-games/` on the machine — outside the repo and the synced runtime folder, so they survive reboots and repo updates. The repo carries no game list; `stock-games/` seeds the folder at setup (e.g. Controller Test).

**Load games from a USB stick (no reboot):**

1. Export your game as a `.png` from the MakeCode Arcade editor, then upload it to the [PNG to JavaScript compiler](https://www.makecode.games/compilers) to get a `.js` file.
2. Copy files onto a USB stick, either:
   - Loose at the drive root: `MyGame.js` plus an optional `MyGame.png` cover image
   - Or inside an `arcade-games/` folder — everything in the folder is installed, so you can dump a whole games library (including `games.json` to keep `name`/`author`/`playerCount`) in one shot

   See `example-usb/` for a ready-to-copy stick layout (copy its contents to the drive root).
3. Plug the stick into the arcade. The game appears in the menu within seconds and stays installed after reboots.

Optional metadata: put `MyGame.json` next to `MyGame.js` to set `name`, `author`, and `playerCount`:

```json
{"name": "My Game", "author": "Sam", "playerCount": 2}
```

By default the menu splits the filename on camelCase (`LouisaMushrooms.js` → author "Louisa", name "Mushrooms"). You can also edit `/home/pi/arcade-games/games.json` on the machine directly — hand edits survive USB updates.

**Menu tiles:** any `games.json` entry with an empty `file` is a decorative tile (e.g. a "Your Game Here" card or a QR code). Its `image` names a `.png` in `arcade-games/`. Add one per machine via USB or by editing `games.json` — nothing tile-related ships in the repo.

**Archiving a game (hide without deleting):** in the menu, press **B five times** (quickly) and hold the fifth press for 5 seconds — the only visible cue is a subtle red border on the selected card. Press **A** to archive, or release B to cancel. The game's files move to `/home/pi/arcade-games/.archived/` and it disappears from the menu. To restore, move the files back into `/home/pi/arcade-games/` and run the regen command below.

**Regenerating the list by hand:** `python3 /usr/local/sbin/arcade-regen-games.py /home/pi/arcade-games` rebuilds `games.json` from the `.js` files present.

## Per-Machine Config (`config.json`)

`/home/pi/arcade-games/config.json` holds machine-specific settings — seeded from `stock-games/` at setup (seed never overwrites, so edits are safe). It can also be installed from a USB stick inside `arcade-games/`.

```json
{
  "attractLines": [
    "These games were made by students of the",
    "*\"Make Video Games\"* class.",
    "Sign up today!"
  ],
  "display": {
    "offsetX": 0,
    "offsetY": 0,
    "scale": 1.0
  }
}
```

- `attractLines` — the title/idle screen text, one array item per line. Wrap a word in `*asterisks*` for the accent color.
- `display.offsetX` / `offsetY` — shift the whole menu screen in real pixels, for bezels or off-center displays.
- `display.scale` — extra zoom multiplier on top of the auto-fit (`1.0` = normal, `0.9` shrinks 10%).
- `exitButtons` — gamepad button indices that kill the running game back to the menu (default `[8, 9]` = Start/Select). Wire a dedicated cabinet reset button into a USB encoder input and set its index here.
- Missing or invalid `config.json` falls back to the built-in defaults. The page picks up changes on its next idle cycle.
