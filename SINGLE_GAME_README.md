# Single Native Arcade — Quick Reference

## Current default game

The active game is set by `SINGLE_GAME_NAME` in the login profile. To change it, re-run the installer:

```bash
cd /home/pi/CreationStationArcade-src
sudo bash install/single-native-arcade-setup.sh --game=YourGameName
sudo reboot
```

## Reset button

- The reset button is read from `arcade.cfg` (`BTN_RESET`, default BCM 4).
- Pressing it kills the current `Game` process; `launcher.sh` restarts it automatically.

## Environment variables

- `SINGLE_GAME_NAME` — name of the active `games/<Name>/` directory.
- `CSA_SOURCE_DIR` — path to the source repo (default `/home/pi/CreationStationArcade-src`).
- `SDL_VIDEODRIVER=kmsdrm` — use the Linux DRM/KMS backend.
- `SDL_AUDIODRIVER=alsa` — use ALSA for audio.
- `LD_LIBRARY_PATH` — set to the active game directory so `libpxt.so` is found.

## Useful files

- `/home/pi/CreationStationArcade/launcher.sh` — main autologin launcher loop.
- `/home/pi/CreationStationArcade/single-native-launch.sh` — wraps `./Game -f` and writes the PID file.
- `/tmp/creationstation_current_game.pid` — PID of the current `Game` process.
- `/home/pi/arcade.log` — log output from the launcher and monitor.

## Change the game

1. Add or replace the `games/<Name>/Game` and `games/<Name>/libpxt.so` files.
2. Re-run `install/single-native-arcade-setup.sh --game=<Name>`.
3. Reboot.
