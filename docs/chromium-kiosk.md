# Chromium Kiosk (Menu)

## What this is / who it's for

This is the **menu** flavor that runs games inside a fullscreen Chromium browser. A small Node server on the Pi serves a menu of games; when you pick one, it opens in a separate fullscreen Chromium window. Because it uses the real MakeCode Arcade simulator in the browser, you get the full extension support you'd see in the simulator — handy for games that use features the raw ELF path can't do.

It's the best choice if you:

- Have a **Raspberry Pi 5** or a **regular x86 PC** (it needs more power than the ELF flavors).
- Want a **menu of games**.
- Want the full MakeCode Arcade simulator capability (extensions and all).

!!! tip "Just one game?"
        If you'd rather boot straight into a single game in Chromium, use the [Chromium Single-Game](single-game-kiosk.md) guide instead — it's the same base, just simplified for one game.

!!! note "Why not a Pi 3?"
        The ELF flavors don't work on a Pi 5 (the "Hardware" line gotcha), so on a Pi 5 you use Chromium or Native instead. Chromium is heavier on the Pi than the ELF path, so it wants a Pi 5 (or a PC), not a Pi 3.

## What you'll need

**Hardware**

- A **Raspberry Pi 5**, or a **regular x86 PC** (64-bit, Debian/Ubuntu-based).
- A microSD card (for a Pi) or a hard drive/SSD (for a PC).
- A power supply.
- An HDMI screen.
- A **USB gamepad** or USB zero-delay encoder. (GPIO virtual gamepads are supported too — see the `--gpio-controllers` option in Step 5.)
- A way to put the SD card into your regular computer (Pi only).
- An internet connection.

**On your regular computer**

- A web browser (to download the OS and to make games in MakeCode Arcade).

## The walkthrough

### Step 1 — Flash the operating system

For a **Raspberry Pi 5**, use the **64-bit Lite** version of Raspberry Pi OS.

1. On your regular computer, download **Raspberry Pi Imager** from <https://www.raspberrypi.com/software/>.
2. Put the microSD card into your computer.
3. Open Raspberry Pi Imager.
4. Under **Choose OS**, pick **Raspberry Pi OS (Other)** → **Raspberry Pi OS Lite (64-bit)**.
5. Under **Choose Storage**, pick your microSD card.
6. Click **Write** and wait for it to finish.

!!! note "What this does"
        Copies a fresh, minimal 64-bit operating system onto the SD card. Use 64-bit — the Pi 5 needs it.

For a **regular PC**, install a 64-bit Debian or Ubuntu server (no desktop needed). The setup script will install the graphical pieces it requires.

### Step 2 — Boot and get online

1. Boot the machine and log in (Pi defaults: `pi` / `raspberry`).
2. Connect to the internet. On a Pi, the easiest way is:

    ```bash
    sudo raspi-config
    ```

    !!! note "What this does"
            Opens the Pi's settings menu. Go to **System Options → Wireless LAN**, pick your country, type your Wi-Fi name and password, then finish.

3. Check the connection:

    ```bash
    ping -c 3 google.com
    ```

    !!! note "What this does"
        Sends three test messages to the internet. Replies mean you're online.

### Step 3 — Install the download tool

```bash
sudo apt install git
```

!!! note "What this does"
        Installs `git`, the program that copies code projects from the internet onto your machine.

### Step 4 — Download the arcade project

```bash
git clone -b chromium-kiosk https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src
```

!!! note "What this does"
        Copies the Creation Station Arcade project into a folder called `CreationStationArcade-src`. The `-b chromium-kiosk` part grabs the Chromium menu flavor specifically. (On a PC, you can clone it wherever you like; the rest of this guide assumes `/home/pi/CreationStationArcade-src`.)

### Step 5 — Run the one-shot setup script

This flavor has a single setup script that does almost everything: installs Chromium, Node, and X; sets up auto-login; applies the Pi 5 graphics fix; creates the runtime folder; sets up background game updates; and hides the boot text.

```bash
bash /home/pi/CreationStationArcade-src/install/kiosk-setup.sh
```

!!! note "What this does"
        The all-in-one installer for this flavor. It installs the packages, configures the Pi to auto-log in and start a graphical session, creates a separate "runtime" folder the arcade runs from, and turns on a background service that pulls game updates on boot.

!!! tip "Using GPIO buttons instead of USB gamepads?"
        If you're wiring real arcade buttons to the Pi's GPIO pins (instead of using USB gamepads), add the flag:

        ```bash
        bash /home/pi/CreationStationArcade-src/install/kiosk-setup.sh --gpio-controllers
        ```

        !!! note "What this does"
                Installs the GPIO virtual-gamepad pieces (the `RPi.GPIO` and `uhid` Python modules) and turns on the GPIO gamepad service. Without this flag, the setup assumes standard USB controllers.

### Step 6 — (Optional) Set up USB controller player assignments

If you're using USB gamepads and you want each USB port to always map to the same player number (so player 1 is always player 1, no matter what order things boot in), plug in your controllers and run:

```bash
sudo bash /home/pi/CreationStationArcade-src-run/setup-usb-controllers.sh
```

!!! note "What this does"
        Creates stable controller-to-player mappings based on which USB port each controller is plugged into. Run this after your controllers are plugged in. Skip it if you're using GPIO buttons.

### Step 7 — Reboot and play

```bash
sudo reboot
```

When the machine comes back up, it should auto-log in, start the graphical session, and show the game menu. Plug in your USB gamepad and pick a game.

## Putting games on the arcade

Games in this flavor are a `.js` file plus a matching `.png` image, listed in a `games.json` file.

1. Export your compiled MakeCode Arcade game as a `.js` file.
2. Drop the `.js` file **and** a matching `.png` image into the `games/` folder.
3. Regenerate the game list:

    ```bash
    bash games/refresh_games.sh
    ```

    !!! note "What this does"
        Rebuilds `games.json` from the files in `games/`. You can also edit `games.json` by hand to set each game's `name`, `author`, and `playerCount`.

4. Save the change to the project and upload it (push it through git).
5. Reboot the arcade. The launcher pulls the latest code on boot and syncs it into the runtime folder, so your new game appears after the reboot.

## If something goes wrong

### "Cannot run in framebuffer mode" (Pi 5 graphics error)

This is the Pi 5 graphics fix, and the setup script applies it automatically (it writes an X11 config that uses the `modesetting` driver on `/dev/dri/card1`). If you still see this error, re-run the setup script from Step 5 — it rewrites the config at `/etc/X11/xorg.conf.d/99-pi-kiosk.conf`.

### No HDMI audio

This flavor includes the same HDMI audio fix as the others. Run it and reboot:

```bash
sudo /home/pi/CreationStationArcade-src-run/install/hdmi-audio-fix.sh
sudo reboot
```

!!! note "What this does"
        Copies in corrected HDMI audio settings and backs up your old ones. Reboot so they load.

### USB controllers aren't detected

Check what the system sees:

```bash
ls /dev/input/js*
```

!!! note "What this does"
        Lists the joystick devices the system has found. If nothing appears, your controller isn't being recognized — try a different USB port or cable. If devices appear but player numbers are wrong, re-run the USB controller setup from Step 6.

### GPIO buttons don't work

GPIO buttons need the `--gpio-controllers` flag during setup (Step 5). If you set up without it, re-run the setup script with the flag. Also note: on a **Pi 5**, the old `wiringPi` library is gone, so GPIO button wiring is limited — USB controllers are more reliable on a Pi 5.

### The arcade boots to a text prompt instead of the menu

The auto-login or the graphical session start may have been reset. Re-run the setup script from Step 5 (it rewrites the auto-login and the `.xinitrc` that starts the menu), then reboot.

### I need a normal prompt to fix something

Log in as a different user (if you made an admin account), or switch to a second virtual terminal with `Ctrl+Alt+F2`. From there you can re-run the setup script or edit files. The runtime folder is at `/home/pi/CreationStationArcade-src-run` and the source folder is at `/home/pi/CreationStationArcade-src`.
