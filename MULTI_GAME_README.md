# Multi Native Arcade — Quick Reference

## How games get picked

`launcher.sh` boots the **menu game** (`games/Menu/` by default, override with
`ARCADE_MENU_NAME`). The menu is a normal native `Game` binary built with the
menu-enabled compiler. When the player picks a game, the menu writes the
game's `games/<Name>` directory name to the launch-request file
(`/tmp/creationstation_launch_request`, override with `ARCADE_LAUNCH_FILE`)
and exits. `launcher.sh` reads the request, launches that game, and goes back
to the menu when it exits.

## Games layout

- `games/Menu/` — the menu game itself.
- `games/<Name>/Game` — native Game executable.
- `games/<Name>/libpxt.so` — PXT VM library for that game (extracted with `Game` from the tar.gz).
- `games/<Name>/cover.png` — optional cover art the menu can show via `control.programImage(name)`; decoded and quantized onto the 16-color palette (keep it small, e.g. 60x34).
- `games/<Name>/cover.img` — optional alternative: a MakeCode image binary returned to `image.ofBuffer()` as-is.
- `games/<Name>/info.json` — optional metadata the menu reads via `control.programInfo(name)`, e.g. `{"name": "Cool Game", "players": 2}`.

## Exit back to the menu

Any `Game` that exits (cleanly or otherwise) returns to the menu. The
`BTN_EXIT` line in `/etc/arcade.cfg` wires a cabinet button to that.

## Reset

The native `Game` handles reset with the `r` / `R` key.

A dedicated cabinet reset button can be wired to **GPIO 14** (physical pin **8**) and **GND** (physical pin **6**). The `launcher.sh` starts `gpio-reset-keyboard.py` automatically; when the switch pulls GPIO 14 to ground, the helper injects an `r` key event, triggering `control.reset()` inside the running `Game` without restarting the process.

- Pin 8: switch wire
- Pin 6: GND (right next to pin 8)

GPIO 14 is the only header pin not assigned in the default `/etc/arcade.cfg` button map, so it won't conflict with player buttons. It's also UART TX, so the serial console must be off (the Pi OS default).

Use a momentary normally-open switch. The pin is pulled up internally, so the button is active-low.

USB gamepads and keyboards still control the game normally, but only the cabinet GPIO button or a physical `r` key press will soft-reset.

## Environment variables

- `ARCADE_GAMES_DIR` — exported by `launcher.sh`; the menu scans it for `*/Game` to build the game list (`control.programList()` in the MakeCode game).
- `ARCADE_LAUNCH_FILE` — path the menu writes the chosen game name to before exiting (default `/tmp/creationstation_launch_request`).
- `ARCADE_MENU_NAME` — directory name of the menu game (default `Menu`).
- `SDL_VIDEODRIVER=kmsdrm` — use the Linux DRM/KMS backend.
- `SDL_AUDIODRIVER=alsa` — use ALSA for audio.
- `SDL_RENDER_DRIVER=opengles2` — force the OpenGL ES 2.0 renderer on ARM boards (set by `launcher.sh` on `aarch64`).
- `LD_LIBRARY_PATH` — set to the running game's directory so `libpxt.so` is found.

## Useful files

- `/home/pi/CreationStationArcade/launcher.sh` — main autologin menu loop.
- `/home/pi/CreationStationArcade/launch-game.sh` — wraps `./Game -f` and writes the PID file.
- `/tmp/creationstation_launch_request` — pending game to launch next.
- `/tmp/creationstation_current_game.pid` — PID of the current `Game` process.
- `/home/pi/arcade.log` — log output from the launcher.

## Add a game

1. Extract a `.tar.gz` from the PNG to Desktop compiler into `games/<Name>/`.
2. It appears in the menu automatically — no reinstall or reboot needed.
3. Or drop the `.tar.gz` on a USB stick and plug it in; the box installs it and launches it immediately.
