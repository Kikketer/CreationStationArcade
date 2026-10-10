# Single Native Arcade — Quick Reference

## Current default game

The active game is set by `SINGLE_GAME_NAME` in the login profile. To change it, re-run the installer:

```bash
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGameName
sudo reboot
```

## Games layout

- `games/<Name>/Game` — native Game executable.
- `games/<Name>/libpxt.so` — PXT VM library for that game (extracted with `Game` from the tar.gz).

## Reset

The native `Game` handles reset with the `r` / `R` key.

A dedicated cabinet reset button can be wired to **GPIO 14** (physical pin **8**) and **GND** (physical pin **6**). The `launcher.sh` starts `gpio-reset-keyboard.py` automatically; when the switch pulls GPIO 14 to ground, the helper injects an `r` key event, triggering `control.reset()` inside the running `Game` without restarting the process.

- Pin 8: switch wire
- Pin 6: GND (right next to pin 8)

GPIO 14 is the only header pin not assigned in the default `/etc/arcade.cfg` button map, so it won't conflict with player buttons. It's also UART TX, so the serial console must be off (the Pi OS default).

Use a momentary normally-open switch. The pin is pulled up internally, so the button is active-low.

USB gamepads and keyboards still control the game normally, but only the cabinet GPIO button or a physical `r` key press will soft-reset.

## Environment variables

- `SINGLE_GAME_NAME` — name of the active `games/<Name>/` directory.
- `SDL_VIDEODRIVER=kmsdrm` — use the Linux DRM/KMS backend.
- `SDL_AUDIODRIVER=alsa` — use ALSA for audio.
- `SDL_RENDER_DRIVER=opengles2` — force the OpenGL ES 2.0 renderer on ARM boards (set by `launcher.sh` on `aarch64`).
- `LD_LIBRARY_PATH` — set to the active game directory so `libpxt.so` is found.

## Useful files

- `/home/pi/CreationStationArcade/launcher.sh` — main autologin launcher loop.
- `/home/pi/CreationStationArcade/single-native-launch.sh` — wraps `./Game -f` and writes the PID file.
- `/tmp/creationstation_current_game.pid` — PID of the current `Game` process.
- `/home/pi/arcade.log` — log output from the launcher.

## Change the game

1. Add a new `games/<Name>/` folder with `Game` and `libpxt.so`.
2. Re-run `install/single-native-arcade-setup.sh --game=<Name>`.
3. Reboot.
