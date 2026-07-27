# Single Native Arcade — Quick Reference

## Current default game

The active game is set by `SINGLE_GAME_NAME` in the login profile. To change it, re-run the installer:

```bash
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGameName
sudo reboot
```

## Reset

The native `Game` handles reset with the `r` / `R` key. The exact button on your USB controller depends on its mapping. No external reset monitor is running in this first pass.

## Environment variables

- `SINGLE_GAME_NAME` — name of the active `games/<Name>/` directory.
- `SDL_VIDEODRIVER=kmsdrm` — use the Linux DRM/KMS backend.
- `SDL_AUDIODRIVER=alsa` — use ALSA for audio.
- `LD_LIBRARY_PATH` — set to the active game directory so `libpxt.so` is found.

## Useful files

- `/home/pi/CreationStationArcade/launcher.sh` — main autologin launcher loop.
- `/home/pi/CreationStationArcade/single-native-launch.sh` — wraps `./Game -f` and writes the PID file.
- `/tmp/creationstation_current_game.pid` — PID of the current `Game` process.
- `/home/pi/arcade.log` — log output from the launcher.

## Change the game

1. Add or replace the `games/<Name>/Game` and `games/<Name>/libpxt.so` files.
2. Re-run `install/single-native-arcade-setup.sh --game=<Name>`.
3. Reboot.
