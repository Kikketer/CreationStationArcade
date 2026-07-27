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
git clone -b single-native-arcade https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade

# 3. Run the installer from the checkout
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGameName

# 4. Reboot
sudo reboot
```

If `--game` is omitted, the installer picks the first valid `games/<Name>/Game` + `libpxt.so` it finds.

## How it works

- `install/single-native-arcade-setup.sh` installs packages, adds the user to required groups, enables `getty@tty1` autologin, and writes the auto-launch block into `~/.bash_profile` and `~/.profile`.
- On boot, the autologin shell runs `launcher.sh` from the checkout directory (`/home/pi/CreationStationArcade`).
- `launcher.sh` picks `SINGLE_GAME_NAME`, sets `SDL_VIDEODRIVER=kmsdrm` and `SDL_AUDIODRIVER=alsa`, then calls `single-native-launch.sh` in a restart loop.
- `single-native-launch.sh` writes the running `Game` PID to `/tmp/creationstation_current_game.pid` and runs `./Game -f` in the game directory.
- The native `Game` has its own reset path (press `r` / `R` for the menu/reset). We are intentionally **not** running an external GPIO kill script for this first pass.

## Add a game from make-web /desktop

1. In the `make-web` `/desktop` tool, upload your MakeCode Arcade PNG export and choose the target architecture:
   - `arm64` for Raspberry Pi
   - `x86-64` for a PC
2. Download the `SafeName{-arm64}.tar.gz` archive.
3. Extract into the checkout:

   ```bash
   cd /home/pi/CreationStationArcade
   mkdir -p games/SafeName
   tar xzf SafeName-arm64.tar.gz -C games/SafeName
   chmod +x games/SafeName/Game
   ```

4. Commit and push the `single-native-arcade` branch (optional, but keeps the source of truth in git).
5. Re-run the installer and reboot:

   ```bash
   cd /home/pi/CreationStationArcade
   sudo bash install/single-native-arcade-setup.sh --game=SafeName
   sudo reboot
   ```

## Change the active game

This branch has no menu. To switch games, replace or add the `games/<Name>/` folder and re-run the installer with the new `--game` value, then reboot.

## Kill or restart the game

- **In-game reset**: the native `Game` handles reset via the `r` / `R` key. Your USB controller's reset mapping depends on its button-to-key configuration.
- **SSH recovery**: log in as an admin user and run:

  ```bash
  sudo pkill -9 -f "games/[^/]+/Game"
  sudo pkill -9 -f launcher.sh
  ```

  Then see `notes.md` for restoring the launcher shell.

## Input strategy

This branch uses **Direct SDL joystick**. USB gamepads and zero-delay encoders that appear as `/dev/input/js*` or `/dev/input/event*` are handled directly by the native `Game` binary. No Python input bridge is required.

## Branch safety

- Do **not** merge `single-native-arcade` into `main`.
- Do **not** add a second game menu here. Multi-game selection belongs in a separate branch.
- Keep this branch minimal: only the files required to clone, install, and boot one game.
