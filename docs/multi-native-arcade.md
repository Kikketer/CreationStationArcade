# Multi-Native Arcade (Menu)

## What this is / who it's for

This is the **menu** flavor that runs games as **native compiled programs** — no browser at all. Each MakeCode Arcade game is compiled to a real `Game` binary (SDL2) by the [PNG to Desktop compiler](https://www.makecode.games/compilers/desktop), and the menu itself is also a MakeCode game that picks which binary to launch.

It's the best choice if you:

- Have a **64-bit Raspberry Pi (3, 4, 5, or Zero 2 W)** — the binaries are `aarch64`, so a 64-bit OS is required. Original Pi Zero / Pi 1 are *not* supported.
- Want a **menu of games** with the fastest possible startup and runtime performance.
- Want GPIO-wired arcade buttons (works great on this flavor) or USB gamepads.

!!! tip "Just one game?"
    The [Native SDL Single-Game](single-native-arcade.md) flavor runs a single native game with an even simpler setup.

## What you'll need

**Hardware**

- A 64-bit Raspberry Pi (3/4/5/Zero 2 W), or a 64-bit ARM/x86 machine.
- A microSD card and power supply.
- An HDMI screen.
- USB gamepads **or** GPIO-wired buttons + a dedicated reset button.
- A **USB stick** for loading games.

**On your regular computer**

- A web browser — for the [PNG to Desktop compiler](https://www.makecode.games/compilers/desktop).

## The walkthrough

### Step 1 — Compile your games

Upload each MakeCode Arcade PNG export to the compiler:

- **Pi**: choose **arm64**
- **x86 PC**: choose **x86-64**
- The **menu project** must also be compiled, with the menu-enabled runtime — it's a MakeCode game like any other.

Each download is a `.tar.gz` containing a `Game` binary.

### Step 2 — Install the OS and clone

Flash **64-bit Lite** OS, create user `pi`, then:

```bash
sudo apt update && sudo apt install -y git
git clone -b multi-native-arcade https://github.com/Kikketer/CreationStationArcade /home/pi/CreationStationArcade
```

### Step 3 — Seed games and run setup

Extract each game into `games/<Name>/` first (each folder holds its `Game` binary and assets), then:

```bash
cd /home/pi/CreationStationArcade
sudo bash install/multi-native-arcade-setup.sh --gpio     # --gpio for GPIO buttons; omit for USB
sudo reboot
```

The installer handles: SDL2/Mesa packages, user groups (`video`, `input`, `audio`, `gpio`), the `vc4-kms-v3d` overlay on Pi, autologin + auto-launch, the KMS/DRM runtime environment, and the USB game-update service.

After reboot the box boots into `games/Menu/Game -f` — or the first valid game if no menu is installed. If no games exist at all, the launcher falls back to **Controller Test**.

### Step 4 — GPIO reset button

A dedicated reset button sends a soft reset (`control.reset`) to the running `Game` via a uinput virtual keyboard (`r` key) — the process never exits.

Default wiring: one side to **GPIO 14 (pin 8)**, other side to **GND (pin 6)**.

### Step 5 — Load games from USB

Drop `.tar.gz` game packages (from the compiler) onto a USB stick and plug it in — the udev-driven update service extracts and installs them, and they appear in the menu without a reboot.

### Hidden gestures

- **Archive a game**: in the menu, B×5 quickly, hold the 5th for ~5s → armed → the **cabinet reset button** confirms; the game's folder moves to `games/.archived/` (restore by moving it back). Release B to cancel.

### Stats

`~/arcade-stats.json` tracks game launches, button presses, `first_seen`, `last_updated` — same format as the other flavors.

## If something goes wrong

- **Nothing on screen**: check `~/arcade.log`; make sure SDL can use `kmsdrm` (the setup sets `SDL_VIDEODRIVER=kmsdrm` / `SDL_RENDER_DRIVER=opengles2`).
- **GPIO dead on Pi 5**: the GPIO shim package differs by model — re-run the setup script.
- **Menu missing**: without `games/Menu/Game`, the launcher starts the first valid game — install a menu build to get the picker back.
