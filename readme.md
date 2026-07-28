# Creation Station Arcade — Single Native Kiosk

This branch (`single-native-arcade`) is a **minimal, single-game launcher** for the native MakeCode Arcade `Game` binary produced by `make-web` `/desktop`.

Do **not** merge this branch into `main` or any other kiosk branch. Each kiosk flavor is standalone.

The `Game` binary is a plain SDL2 executable. It does **not** choose a display backend or renderer for you, so you must configure the runtime environment for your target. The two common setups are below.

## Pick your environment

<details>
<summary>Desktop Linux (x86-64, Debian/Ubuntu with a desktop)</summary>

For testing or playing on a regular PC:

1. In `make-web` `/desktop`, upload your MakeCode Arcade PNG export and choose **x86-64**.
2. Download the tar.gz and extract:

   ```bash
   mkdir -p ~/Games/MyGame
   tar xzf MyGame.tar.gz -C ~/Games/MyGame
   chmod +x ~/Games/MyGame/Game
   ```

3. Install SDL2 and Mesa:

   ```bash
   sudo apt update
   sudo apt install -y libsdl2-2.0-0 libgl1-mesa-dri
   ```

4. Run:

   ```bash
   cd ~/Games/MyGame
   ./Game
   ```

   Use `./Game -f` for fullscreen. SDL will use X11 or Wayland automatically with the default OpenGL renderer.

</details>

<details>
<summary>Standalone arcade cabinet (ARM64, e.g., Raspberry Pi, no desktop)</summary>

For a Pi or similar ARM board that boots straight into the game:

- Supported Pi models: Pi 3, Pi 4, Pi 5, and Pi Zero 2 W (all with a 64-bit OS). Original Pi Zero / Pi 1 are not supported because the `Game` binary is `aarch64`.

1. In `make-web` `/desktop`, upload your MakeCode Arcade PNG export and choose **arm64**.
2. On the target machine:

   ```bash
   sudo apt update && sudo apt install -y git
   git clone -b single-native-arcade https://github.com/Kikketer/CreationStationArcade /home/pi/CreationStationArcade
   cd /home/pi/CreationStationArcade
   sudo bash install/single-native-arcade-setup.sh --game=YourGame
   sudo reboot
   ```

   The installer handles:
   - Packages: `libsdl2-2.0-0`, `libdrm2`, `libgbm1`, `libudev1`, `libasound2`, `libgl1-mesa-dri`, `libegl1`, `libgles2`
   - User groups: `video`, `input`, `audio`
   - Pi `vc4-kms-v3d,cma-128` overlay (when a Raspberry Pi is detected)
   - `getty@tty1` autologin and the auto-launch block in `~/.bash_profile`/`~/.profile`
   - Runtime environment: `SDL_VIDEODRIVER=kmsdrm` and `SDL_RENDER_DRIVER=opengles2`

3. After reboot, the cabinet boots straight into `./Game -f` in `games/<YourGame>/`.

If `--game` is omitted, the installer picks the first valid `games/<Name>/` folder.

To disable autolaunch for debugging, see `notes.md` or run `./toggle-arcade.sh disable`.

</details>

## Hardware requirements

- 64-bit Raspberry Pi or PC running a 64-bit Debian-based Linux (`arm64` or `x86-64`).
  - For Raspberry Pi, the installer enables the `vc4-kms-v3d` overlay in `/boot/firmware/config.txt` (or `/boot/config.txt`) so KMSDRM has a DRM device.
- SDL2 / GL runtime libraries installed by the installer (`libsdl2-2.0-0`, `libdrm2`, `libgbm1`, `libudev1`, `libasound2`, `libgl1-mesa-dri`, `libegl1`, `libgles2`).
- The arcade user must belong to the `video` group for KMSDRM.

## How it works

- `install/single-native-arcade-setup.sh` installs packages, adds the user to required groups, enables `getty@tty1` autologin, and writes the auto-launch block into `~/.bash_profile` and `~/.profile`.
- On boot, the autologin shell runs `launcher.sh` from the checkout directory (`/home/pi/CreationStationArcade`).
- `launcher.sh` picks `SINGLE_GAME_NAME`, sets `SDL_VIDEODRIVER=kmsdrm`, `SDL_AUDIODRIVER=alsa`, and `SDL_RENDER_DRIVER=opengles2` on `aarch64`, then calls `single-native-launch.sh` in a restart loop.
- `single-native-launch.sh` writes the running `Game` PID to `/tmp/creationstation_current_game.pid` and runs `./Game -f` inside `games/<Name>/`.
- The native `Game` has its own reset path (press `r` / `R` for the menu/reset). We are intentionally **not** running an external GPIO kill script for this first pass.

## Add a game from make-web /desktop

1. In the `make-web` `/desktop` tool, upload your MakeCode Arcade PNG export and choose the target architecture:
   - `arm64` for Raspberry Pi / ARM arcade cabinets
   - `x86-64` for desktop Linux PCs
2. Download the `SafeName{-arm64}.tar.gz` archive.
3. Extract into `games/<Name>/`:

   ```bash
   cd /home/pi/CreationStationArcade
   mkdir -p games/SafeName
   tar xzf SafeName-arm64.tar.gz -C games/SafeName
   chmod +x games/SafeName/Game
   ```

   The archive contains `Game` and `libpxt.so`; both must stay in `games/SafeName/`.

4. Commit and push the `single-native-arcade` branch (optional, but keeps the source of truth in git).
5. For an arcade cabinet, re-run the installer and reboot:

   ```bash
   cd /home/pi/CreationStationArcade
   sudo bash install/single-native-arcade-setup.sh --game=SafeName
   sudo reboot
   ```

   On a desktop, just run the extracted `Game` binary directly.

## Change the active game

This branch has no menu. To switch games, add a new `games/<Name>/` folder and re-run the installer with the new `--game` value, then reboot.

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
