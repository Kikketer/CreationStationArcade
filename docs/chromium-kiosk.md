# Chromium Kiosk (Menu)

## What this is / who it's for

This is the **menu** flavor that runs games inside a fullscreen Chromium browser. A small Node server on the machine serves a menu of games; when you pick one, it opens in a separate fullscreen Chromium window. Because it uses the real MakeCode Arcade simulator in the browser, you get the full extension support you'd see in the simulator — handy for games that use features the raw ELF path can't do.

It's the best choice if you:

- Have a **Raspberry Pi 5** or a **regular x86 PC** (it needs more power than the ELF flavors).
- Want a **menu of games** you can update from a USB stick.
- Want the full MakeCode Arcade simulator capability (extensions and all).

!!! tip "Just one game?"
    If you'd rather boot straight into a single game in Chromium, use the [Chromium Single-Game](single-game-kiosk.md) guide instead.

!!! note "Why not a Pi 3?"
    The ELF flavors don't work on a Pi 5 (the "Hardware" line gotcha), so on a Pi 5 you use Chromium or Native instead. Chromium is heavier on the Pi than the ELF path, so it wants a Pi 5 (or a PC), not a Pi 3.

## What you'll need

**Hardware**

- A **Raspberry Pi 5**, or a **regular x86 PC** (64-bit, Debian/Ubuntu-based).
- A microSD card (for a Pi) or a hard drive/SSD (for a PC).
- A power supply.
- An HDMI screen.
- A **USB gamepad** or USB zero-delay encoder. (GPIO-wired buttons are supported too — see the `--gpio-controllers` option in Step 4.)
- A **FAT32 USB stick** for loading games and per-machine config.
- A way to put the SD card into your regular computer (Pi only).
- An internet connection (for setup only — the arcade runs fine offline).

**On your regular computer**

- A web browser (to download the OS and to make games in MakeCode Arcade).

## The walkthrough

### Step 1 — Install the operating system

- **Raspberry Pi 5**: flash **Raspberry Pi OS Lite (64-bit)** with the Raspberry Pi Imager. When it asks you to create a user, **name it `pi`** — the Pi scripts assume that account.
- **x86 PC**: install **64-bit Debian or Ubuntu server** — no desktop environment needed (the setup script installs the graphical bits itself). Leave the root password blank during install so your normal user gets `sudo` automatically. The user can be named anything.

### Step 2 — Clone the repo

Log in as your normal user, then:

```bash
sudo apt update && sudo apt install -y git
git clone -b chromium-kiosk https://github.com/Kikketer/CreationStationArcade ~/CreationStationArcade-src
```

### Step 3 — Run the setup script

- **x86 PC**:
  ```bash
  sudo bash ~/CreationStationArcade-src/install/debian-x86-setup.sh
  ```
- **Raspberry Pi** (USB gamepads):
  ```bash
  sudo bash ~/CreationStationArcade-src/install/kiosk-setup.sh
  ```
- **Raspberry Pi** (GPIO-wired arcade buttons):
  ```bash
  sudo bash ~/CreationStationArcade-src/install/kiosk-setup.sh --gpio-controllers
  ```

Running with `sudo` is safe — the script figures out the real user automatically. It's also idempotent: re-running it just rewrites configs and re-syncs the runtime.

The installer handles: Xorg + Chromium + Node + `openbox` (a minimal window manager — without one, Chromium ignores fullscreen on bare X), autologin on the console, a boot-time update service, the USB game-update service, and seeds `~/arcade-games` with the stock Controller Test.

### Step 4 — Reboot

```bash
sudo reboot
```

The machine comes up straight into the menu. With no games installed you'll see just **Controller Test** — the built-in sanity game that verifies controls. It automatically hides itself once real games are installed.

### Step 5 — Load games from a USB stick

Format a stick as **FAT32**, and put an `arcade-games/` folder at its root:

```
arcade-games/
├── MyGame.js            compiled MakeCode Arcade game
├── MyGame.png           cover art (~60x34 px pixel art)
├── MyGame.json          optional metadata: name/author/playerCount
├── games.json           optional: full curated list (preserves your ordering + tiles)
└── config.jsonc         optional: this machine's settings (see below)
```

Two other layouts also work: loose `.js` + `.png` pairs at the stick root, or a `games.json` for bulk metadata. Plug it in — within a few seconds the files are copied into `~/arcade-games`, the list is rebuilt, and the menu picks them up live. No reboot.

Re-docking the same stick is a no-op (per-file timestamps). Newer files overwrite. `example-usb/` in the repo is a ready-to-copy example payload with a full library.

### Step 6 — Wire a cabinet reset button (optional)

On x86, wire a reset button into the USB encoder like any other button — it shows up as a gamepad button index. Put that index in `config.jsonc` under `exitButtons` (see below). On Pi+GPIO, the GPIO reset button works via the GPIO monitor.

## Per-machine settings (`config.jsonc`)

`~/arcade-games/config.jsonc` holds box-specific settings — seeded at setup, never overwritten by re-running setup, and **round-tripped over USB**: dock a stick and your current config is mirrored onto it so you can edit it on any computer and re-dock.

```jsonc
{
  "attractLines": [ "line 1", "*accented* line 2" ],   // title screen text
  "display": {
    "resolution": "",       // force window size e.g. "1280x1024"; "" = xrandr
    "offsetX": 0,           // shift menu in real pixels (bezel/mask adjustment)
    "offsetY": 0,
    "scale": 1.0            // nudges size; result snaps to a WHOLE number
  },
  "exitButtons": [8, 9]     // gamepad buttons that kill a game back to menu
}
```

Changes apply live — no reboot needed (the menu re-fetches config every 15s).

## Hidden menu gestures

Undiscoverable on purpose — the only visible cue is a thin red border:

- **Archive a game**: press B×5 quickly, hold the 5th B for 5 seconds → the card gets a red outline → press **A** to archive (files move to `~/arcade-games/.archived/`, restorable by moving them back) or release B to cancel.
- **Reorder games**: same gesture, but while still holding B, move the D-pad — the card moves through the list. Release B to save the order (stored in `games.json`, survives reboots and USB docks).

## Stats

`~/arcade-stats.json` accumulates game launch counts, per-button press counts, `first_seen` dates, and `last_updated`. It's outside the synced folders, so updates never touch it — and you can migrate an old file in and it'll keep counting.

## If something goes wrong

- **Black screen**: check `~/arcade.log`. If X is running but nothing else, the launcher never spawned — look for autologin or `.xinitrc` problems. `Ctrl+Alt+F2` gets a normal TTY.
- **Squashed / offset picture**: the menu auto-fits the monitor and snaps to whole-pixel scale; use `display.resolution`/`offsetX`/`offsetY`/`scale` in `config.jsonc` for stubborn panels.
- **USB stick ignored**: it must be FAT32 and contain `arcade-games/` or root-level `.js` files. Watch `tail -f ~/arcade.log` for `usb-update:` lines; `journalctl -u 'arcade-usb-update@*'` shows whether the service fired.
- **GPIO buttons dead on Pi 5**: needs `python3-rpi-lgpio` (setup installs it automatically when it detects a Pi 5). Check `systemctl status gpio-gamepad.service`.
- **Performance floor**: the slowest box this runs acceptably on is roughly an i3-8100 + UHD 630 — see `machine-specs.txt` in the repo. Below that, expect tearing.
