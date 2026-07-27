# Creation Station Arcade — Single Native Kiosk

This branch (`single-native-arcade`) is a **minimal, single-game kiosk** that boots a 64-bit Debian or Raspberry Pi install straight into one native MakeCode Arcade `Game` binary.

Do **not** merge this branch into `main` or any other kiosk branch. Each kiosk flavor is standalone.

## Hardware requirements

- 64-bit Raspberry Pi or PC running a 64-bit Debian-based Linux (`arm64` or `x86-64`).
- SDL2 runtime libraries installed by the installer (`libsdl2-2.0-0`, `libdrm2`, `libgbm1`, `libudev1`, `libasound2`).
- The arcade user must belong to the `video` group for KMSDRM.

## One-command install

```bash
# 1. Install git on the target machine
sudo apt update && sudo apt install -y git

# 2. Clone this branch directly into the runtime folder
git clone -b single-native-arcade https://github.com/Kikketer/CreationStationArcade /home/pi/CreationStationArcade

# 3. Copy the native game(s) and shared lib into games/
#    games/libpxt.so            (one shared PXT VM library for this architecture)
#    games/YourGameName         (the native Game binary, renamed from the tar.gz Game file)

# 4. Run the installer from the checkout
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGameName

# 5. Reboot
sudo reboot
```

If `--game` is omitted, the installer picks the first executable in `games/` (excluding `libpxt.so`).

## How it works

- `install/single-native-arcade-setup.sh` installs packages, adds the user to required groups, enables `getty@tty1` autologin, and writes the auto-launch block into `~/.bash_profile` and `~/.profile`.
- On boot, the autologin shell runs `launcher.sh` from the checkout directory (`/home/pi/CreationStationArcade`).
- `launcher.sh` picks `SINGLE_GAME_NAME`, sets `SDL_VIDEODRIVER=kmsdrm` and `SDL_AUDIODRIVER=alsa`, and runs the chosen executable in `games/`.
- `single-native-launch.sh` writes the running `Game` PID to `/tmp/creationstation_current_game.pid` and runs `./<GameName> -f`.
- The native `Game` has its own reset path (press `r` / `R` for the menu/reset). We are intentionally **not** running an external GPIO kill script for this first pass.
- `libpxt.so` lives once in `games/` and is shared by every `Game` binary in that folder.

## Add a game from make-web /desktop

1. In the `make-web` `/desktop` tool, upload your MakeCode Arcade PNG export and choose the target architecture:
   - `arm64` for Raspberry Pi
   - `x86-64` for a PC
2. Download the `SafeName{-arm64}.tar.gz` archive.
3. Extract into the checkout. The archive usually contains `Game` and `libpxt.so`:

   ```bash
   cd /home/pi/CreationStationArcade
   tar xzf SafeName-arm64.tar.gz -C games
   mv games/Game games/SafeName
   chmod +x games/SafeName
   ```

   Keep one `games/libpxt.so` for the architecture; delete any duplicate copies.

4. Commit and push the `single-native-arcade` branch (optional, but keeps the source of truth in git).
5. Re-run the installer and reboot:

   ```bash
   cd /home/pi/CreationStationArcade
   sudo bash install/single-native-arcade-setup.sh --game=SafeName
   sudo reboot
   ```

## Change the active game

This branch has no menu. To switch games, put a new executable in `games/` and re-run the installer with the new `--game` value, then reboot. Only one `games/libpxt.so` is needed for all games.

## Kill or restart the game

- **In-game reset**: the native `Game` handles reset via the `r` / `R` key. Your USB controller's reset mapping depends on its button-to-key configuration.
- **SSH recovery**: log in as an admin user and run:

  ```bash
  sudo pkill -9 -f "games/[^/ ]+$"
  sudo pkill -9 -f launcher.sh
  ```

  Then see `notes.md` for restoring the launcher shell.

## Input strategy

This branch uses **Direct SDL joystick**. USB gamepads and zero-delay encoders that appear as `/dev/input/js*` or `/dev/input/event*` are handled directly by the native `Game` binary. No Python input bridge is required.

## Branch safety

- Do **not** merge `single-native-arcade` into `main`.
- Do **not** add a second game menu here. Multi-game selection belongs in a separate branch.
- Keep this branch minimal: only the files required to clone, install, and boot one game.
