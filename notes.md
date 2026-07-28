# Recovery notes for single-native-arcade

## Temporarily disable the autologin launcher

Log in from another console/TTY or SSH and run:

```bash
cd /home/pi/CreationStationArcade
./toggle-arcade.sh disable
```

That comments out the launcher block in `~/.bash_profile` and `~/.profile` and kills any running arcade processes.  To re-enable:

```bash
cd /home/pi/CreationStationArcade
./toggle-arcade.sh enable
```

## Kill the running game and launcher

```bash
sudo pkill -9 -f "games/[^/]+/Game"
sudo pkill -9 -f launcher.sh
sudo pkill -9 -f single-native-launch.sh
```

Then clear the screen:

```bash
clear
```

## Test a native game from a console

```bash
cd /home/pi/CreationStationArcade/games/YourGame
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
./Game -f
```

If you get permission errors on `/dev/dri`, make sure the arcade user is in the `video` group and reboot.

## Re-run the installer

```bash
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGame
```

## Raspberry Pi notes

- The installer detects Raspberry Pi and adds `dtoverlay=vc4-kms-v3d,cma-128` to `/boot/firmware/config.txt` or `/boot/config.txt` if it is missing.
- Make sure the OS is 64-bit (`arm64`). The bundled `Game` binaries are 64-bit and will not run on 32-bit `armhf` Pi OS.
- Supported: Pi 3, Pi 4, Pi 5, and Pi Zero 2 W (with a 64-bit OS). Original Pi Zero / Pi 1 are not supported.
- Pi 3 / Zero 2 W use the `vc4` DRI driver; Pi 4 / Pi 5 use the `v3d` DRI driver. Both are included in `libgl1-mesa-dri`.
- If KMSDRM still fails on a Pi, verify the overlay is present and the `video` group membership is active after reboot.

## MESA-LOADER errors or "SDL Error: Invalid window"

If you see `MESA-LOADER: failed to open ..._dri.so` followed by `SDL Error: Invalid window`, the DRI/Mesa drivers are missing or the arcade user cannot access `/dev/dri`.

1. Install the Mesa DRI package:

   ```bash
   sudo apt update
   sudo apt install -y libgl1-mesa-dri
   ```

2. Reboot so the `video` group membership takes effect:

   ```bash
   sudo reboot
   ```

3. To test without a GL driver, use SDL's software renderer:

   ```bash
   cd /home/pi/CreationStationArcade/games/YourGame
   export SDL_VIDEODRIVER=kmsdrm
   export SDL_AUDIODRIVER=alsa
   export SDL_RENDER_DRIVER=software
   ./Game -f
   ```

## Black screen with a cursor (window opens, game does not draw)

If the game opens a window but only shows black with a cursor, the wrong SDL renderer is being selected. On ARM KMSDRM boards, force the GLES2 renderer:

```bash
cd /home/pi/CreationStationArcade/games/YourGame
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export SDL_RENDER_DRIVER=opengles2
./Game -f
```

`launcher.sh` now sets `SDL_RENDER_DRIVER=opengles2` automatically on `aarch64`.
