# Chromium Single-Game

## What this is / who it's for

This is the **single-game** Chromium flavor. It's the [Chromium Kiosk (Menu)](chromium-kiosk.md) base, simplified to boot straight into **one** game instead of showing a menu. A reset button restarts that same game instantly. It uses a single Chromium instance, so it uses less memory and boots faster than the menu version.

It's the best choice if you:

- Have a **Raspberry Pi 5** or a **regular x86 PC**.
- Want a dedicated cabinet for **one** game.
- Want the full MakeCode Arcade simulator capability (extensions and all), but don't need a menu.

!!! tip "Want a menu of games instead?"
        Use the [Chromium Kiosk (Menu)](chromium-kiosk.md) guide — it's the same base with a menu.

## What you'll need

Same as the [Chromium Kiosk (Menu)](chromium-kiosk.md) flavor:

- A **Raspberry Pi 5** or a **regular x86 PC** (64-bit, Debian/Ubuntu-based).
- A microSD card (Pi) or hard drive/SSD (PC), power supply, HDMI screen.
- A **USB gamepad** or USB zero-delay encoder (GPIO buttons also supported).
- A way to put the SD card into your regular computer (Pi only).
- An internet connection.
- A web browser on your regular computer.

## The walkthrough

This flavor is the Chromium kiosk base plus a "single-game" layer on top. So you'll do the Chromium setup first, then switch it into single-game mode.

### Step 1 — Set up the Chromium kiosk base

Follow the **[Chromium Kiosk (Menu)](chromium-kiosk.md)** guide from Step 1 through Step 5, with one change: when you download the project in Step 4, grab the **single-game** branch instead:

```bash
git clone -b single-game-kiosk https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src
```

!!! note "What this does"
        Copies the Creation Station Arcade project into `CreationStationArcade-src`, using the single-game Chromium branch. This branch already contains the single-game launcher and reset scripts, on top of the Chromium kiosk base.

Then run the same one-shot installer:

```bash
bash /home/pi/CreationStationArcade-src/install/kiosk-setup.sh
```

!!! note "What this does"
        The all-in-one Chromium kiosk installer (packages, auto-login, Pi 5 graphics fix, runtime folder, background updates, hidden boot text). Add `--gpio-controllers` if you're wiring real arcade buttons to the GPIO pins instead of using USB gamepads.

When you're done with those steps, come back here to switch the base into single-game mode.

### Step 2 — Pick your game

The single-game launcher reads the game name from a setting called `SINGLE_GAME_NAME`. If you don't set it, it defaults to `AndyPaddleTheRiver`.

Some games already included in the project:

| Game name | Players |
| --- | --- |
| `AndyPaddleTheRiver` | 1 |
| `ChrisGreedyPirates` | 2 |
| `ChrisVikingsOfFour` | 4 |
| `EliSonicMiniboss` | 1 |
| `EliSuperStarStory` | 4 |
| `EvelynBunnyCat` | 1 |
| `KaitoBubbleSlash` | 1 |
| `LucianCave` | 2 |
| `RiojiCat` | 1 |
| `ScottSaveYourself` | 1 |
| `WilliamDoubleDeath` | 1 |
| `WilliamZombie` | 2 |

You'll set this name in the next step.

### Step 3 — Switch the launcher to single-game mode

The Chromium base starts a graphical session that runs `launcher.sh` (the menu launcher). To boot into one game instead, you point that session at the single-game launcher and tell it which game to run.

Edit the file that starts the graphical session. The setup script wrote it at `~/.xinitrc`:

```bash
nano ~/.xinitrc
```

!!! note "What this does"
        Opens the `.xinitrc` file in a simple text editor. This file runs when the graphical session starts.

Find the line that launches the menu launcher:

```bash
exec bash launcher.sh
```

and change it to launch the single-game launcher instead, with your game name set:

```bash
export SINGLE_GAME_NAME="ChrisVikingsOfFour"
exec bash single-game-launcher.sh
```

(Replace `ChrisVikingsOfFour` with your game from the table above.) Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in `nano`).

!!! note "What this does"
        Tells the graphical session to run the single-game launcher instead of the menu launcher, and sets which game it boots into.

### Step 4 — Turn on the single-game reset service

This flavor has its own reset-button service that restarts the current game when you press the reset button (instead of returning to a menu). Turn off the menu's reset service and turn on the single-game one:

```bash
sudo systemctl stop gpio-monitor
sudo systemctl disable gpio-monitor
sudo cp /home/pi/CreationStationArcade-src/gpio-monitor-single-game.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gpio-monitor-single-game
sudo systemctl start gpio-monitor-single-game
```

!!! note "What this does"
        Stops and disables the menu's reset monitor, copies the single-game reset service into place, reloads the service list, then enables and starts the single-game reset monitor. Now the reset button restarts your one game.

### Step 5 — (If using GPIO buttons) Enable the gamepad service

If you set up with `--gpio-controllers`, make sure the GPIO gamepad service is on:

```bash
sudo systemctl enable gpio-gamepad
sudo systemctl start gpio-gamepad
```

!!! note "What this does"
        Turns on the GPIO virtual-gamepad service so your wired buttons work. Skip this if you're using USB gamepads.

### Step 6 — (If using USB gamepads) Set up stable player assignments

```bash
sudo bash /home/pi/CreationStationArcade-src-run/setup-usb-controllers.sh
```

!!! note "What this does"
        Maps each USB port to a fixed player number so player 1 is always player 1. Run this after your controllers are plugged in. Skip it if you're using GPIO buttons.

### Step 7 — Reboot and play

```bash
sudo reboot
```

When the machine comes back up, it should boot straight into your chosen game. The reset button restarts the same game.

## Changing the game later

Edit `~/.xinitrc` again (Step 3) and change the `SINGLE_GAME_NAME` line to a different game name, then reboot.

## Putting a new game on the arcade

1. Export your compiled MakeCode Arcade game as a `.js` file (and a matching `.png` image).
2. Drop both files into the `games/` folder.
3. Regenerate the game list:

    ```bash
    bash games/refresh_games.sh
    ```

    !!! note "What this does"
        Rebuilds `games.json` from the files in `games/`.

4. Update `SINGLE_GAME_NAME` in `~/.xinitrc` (Step 3) to the new game's name.
5. Save the change to the project and upload it (push it through git), then reboot. The launcher pulls the latest code on boot and syncs it into the runtime folder.

## If something goes wrong

### The game won't start

Check the arcade log for clues:

```bash
tail -20 /home/pi/arcade.log
```

!!! note "What this does"
        Prints the last 20 lines of the arcade's log file, which usually says why a launch failed (missing game file, Chromium not found, etc.).

Verify the game file actually exists:

```bash
ls /home/pi/CreationStationArcade-src-run/games/YourGameName.js
```

!!! note "What this does"
        Checks that the `.js` file for your game is in the runtime games folder. If it's missing, the game name in `SINGLE_GAME_NAME` is probably spelled wrong, or the file wasn't synced — reboot once more to let the background update pull it.

### The reset button doesn't restart the game

Check the single-game reset service:

```bash
sudo systemctl status gpio-monitor-single-game
```

!!! note "What this does"
        Shows whether the single-game reset monitor is running. If it's failed or inactive, try `sudo systemctl restart gpio-monitor-single-game`, or reboot.

### USB controllers aren't working

```bash
sudo systemctl status gpio-gamepad
ls /dev/input/js*
```

!!! note "What this does"
        The first command checks the GPIO gamepad service status (only relevant if you use GPIO buttons). The second lists the joystick devices the system sees. If nothing appears, try a different USB port or cable, then re-run the USB controller setup from Step 6.

### I want to switch back to the menu version

Revert Step 3 (change `~/.xinitrc` back to `exec bash launcher.sh`), then re-enable the menu's reset service:

```bash
sudo systemctl stop gpio-monitor-single-game
sudo systemctl disable gpio-monitor-single-game
sudo systemctl enable gpio-monitor
sudo systemctl start gpio-monitor
```

!!! note "What this does"
        Turns the single-game reset monitor back off and turns the menu reset monitor back on, so the reset button returns you to the menu instead of restarting one game.

### I need a normal prompt to fix something

Log in as a different user (if you made an admin account), or switch to a second virtual terminal with `Ctrl+Alt+F2`. The runtime folder is at `/home/pi/CreationStationArcade-src-run` and the source folder is at `/home/pi/CreationStationArcade-src`.
