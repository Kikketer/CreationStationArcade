# Native SDL Single-Game

## What this is / who it's for

This is the **fastest** single-game flavor. Instead of running your game inside a web browser (like the Chromium flavors), it runs a real, compiled `Game` program directly using a graphics library called SDL. No browser, no menu — the cabinet boots straight into one game and runs it as fast as the hardware can.

It's the best choice if you:

- Have a **64-bit Raspberry Pi** (Pi 3, Pi 4, Pi 5, or Pi Zero 2 W) **or** a **64-bit PC** (x86-64).
- Want a dedicated cabinet for **one** game.
- Want the best performance (no browser overhead).
- Are getting your game from the `make-web` `/desktop` tool, which builds the native `Game` binary.

!!! warning "Needs a 64-bit operating system"
        The `Game` binary is a 64-bit (`aarch64`) program. The original Pi Zero and Pi 1 are **not** supported because they're 32-bit only. Use a 64-bit OS on a Pi 3/4/5/Zero 2 W, or a 64-bit PC.

!!! tip "Want a menu, or a browser-based game?"
        This flavor has no menu and no browser. For a menu of games on a Pi 5/PC, use [Chromium Kiosk (Menu)](chromium-kiosk.md). For a single game in a browser, use [Chromium Single-Game](single-game-kiosk.md).

## What you'll need

**Hardware**

- A **64-bit Raspberry Pi** (3, 4, 5, or Zero 2 W) **or** a **64-bit PC** (x86-64, Debian/Ubuntu-based).
- A microSD card (Pi) or hard drive/SSD (PC), power supply, HDMI screen.
- A **USB gamepad** or USB zero-delay encoder. (This flavor reads USB joysticks directly — no Python input bridge needed.)
- **Optional:** a momentary push button and two wires for the GPIO reset button (Raspberry Pi only — see Step 7).
- A way to put the SD card into your regular computer (Pi only).
- An internet connection.

**On your regular computer**

- A web browser, to use the `make-web` `/desktop` tool that builds the native `Game` binary.

## The walkthrough

### Step 1 — Get your game binary from make-web

This flavor runs a native `Game` binary that you build with the `make-web` `/desktop` tool, not a raw `.elf` or a `.js` file.

1. In your browser, open the `make-web` `/desktop` tool.
2. Upload your MakeCode Arcade PNG export.
3. Choose the architecture that matches your cabinet:
    - **arm64** for a Raspberry Pi / ARM arcade cabinet.
    - **x86-64** for a desktop Linux PC.
4. Download the resulting `.tar.gz` archive (for example `SafeName-arm64.tar.gz`).

!!! note "What this does"
        Builds a compiled `Game` program for your target machine and packages it (with its helper library `libpxt.so`) into a downloadable archive.

### Step 2 — Flash the operating system

For a **Raspberry Pi**, use the **64-bit Lite** version of Raspberry Pi OS.

1. On your regular computer, download **Raspberry Pi Imager** from <https://www.raspberrypi.com/software/>.
2. Put the microSD card into your computer.
3. Open Raspberry Pi Imager.
4. Under **Choose OS**, pick **Raspberry Pi OS (Other)** → **Raspberry Pi OS Lite (64-bit)**.
5. Under **Choose Storage**, pick your microSD card.
6. Click **Write** and wait for it to finish.

!!! note "What this does"
        Copies a fresh, minimal 64-bit operating system onto the SD card. 64-bit is required — the `Game` binary won't run on a 32-bit OS.

For a **regular PC**, install a 64-bit Debian or Ubuntu server.

### Step 3 — Boot and get online

1. Boot the machine and log in (Pi defaults: `pi` / `raspberry`).
2. Connect to the internet. On a Pi:

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

### Step 4 — Download the arcade project

```bash
sudo apt update && sudo apt install -y git
git clone -b single-native-arcade https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade
```

!!! note "What this does"
        Updates the package list, installs `git`, then copies the Creation Station Arcade project (the native single-game branch) into `/home/pi/CreationStationArcade`. This flavor runs directly from that folder — there's no separate "runtime" folder like the other flavors.

### Step 5 — Add your game to the project

Put the archive you downloaded in Step 1 onto the Pi (over the network, or by moving the SD card), then extract it into the `games/` folder:

```bash
cd /home/pi/CreationStationArcade
mkdir -p games/MyGame
tar xzf MyGame-arm64.tar.gz -C games/MyGame
chmod +x games/MyGame/Game
```

!!! note "What this does"
        Creates a folder for your game inside `games/`, extracts the archive into it (the archive contains `Game` and `libpxt.so` — both must stay in that folder together), and marks `Game` as runnable. Replace `MyGame` and the archive name with your actual file names.

!!! warning "Keep `Game` and `libpxt.so` together"
        The `Game` program needs `libpxt.so` sitting right next to it in the same folder. Don't move one without the other.

### Step 6 — Run the one-shot setup script

This flavor has a single installer that does almost everything: installs the SDL and graphics libraries, adds your user to the right groups, enables the Pi's graphics overlay (if you're on a Pi), sets up auto-login, writes the auto-launch settings, and marks everything runnable.

```bash
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=MyGame
sudo reboot
```

!!! note "What this does"
        The all-in-one installer for this flavor. Replace `MyGame` with the folder name you created in Step 5 (the name of the folder under `games/`, not the archive). The script installs the libraries the `Game` binary needs, enables the Pi's KMS graphics overlay, sets up auto-login so the cabinet boots straight into the game, and writes the launch settings. The reboot starts it.

!!! tip "No `--game` argument?"
        If you leave off `--game`, the installer picks the first valid game it finds under `games/` (a folder containing both `Game` and `libpxt.so`). That's handy if you only have one game.

!!! note "What the installer sets up behind the scenes"
        On a Raspberry Pi it enables the `dtoverlay=vc4-kms-v3d,cma-128` line in your boot config so the Pi has a graphics device for SDL to use. It also sets the runtime environment variables `SDL_VIDEODRIVER=kmsdrm` and `SDL_RENDER_DRIVER=opengles2` (on ARM64) so the `Game` binary draws to the screen correctly. You don't have to do any of this by hand.

### Step 7 — (Optional) Wire the GPIO reset button

This flavor supports a dedicated cabinet reset button. When you press it, it triggers the game's own soft reset (the same as pressing the `r` key) — the `Game` process never exits, it just restarts inside itself.

**Wiring (Raspberry Pi only):**

- Connect one side of a momentary normally-open push button to **GPIO 27** (physical pin **13**).
- Connect the other side to **GND** (physical pin **14**, right next to pin 13).

```
Pin 13  GPIO 27  -> one switch wire
Pin 14  GND      -> other switch wire
```

Because the button pulls the pin to ground, the launcher runs the reset helper in "active-low" mode by default. To use a different GPIO pin, set `GPIO_RESET_PIN` before rebooting. To use an active-high (3.3 V) button instead, set `GPIO_RESET_ACTIVE_HIGH=1`.

!!! note "What this does"
        The reset button wires to GPIO 27 and ground. The launcher's reset helper watches that pin and, when it's pressed, injects an `r` keypress into the running `Game`, which the game turns into a soft reset. No external kill script runs — the game handles the reset itself.

### Step 8 — Play

After the reboot, the cabinet boots straight into `./Game -f` (fullscreen) inside your `games/MyGame/` folder. Plug in your USB gamepad and play. The reset button (if you wired one) restarts the game.

## Changing the game later

This flavor has no menu. To switch games:

1. Add a new `games/<NewName>/` folder (Step 5) with the new `Game` and `libpxt.so`.
2. Re-run the installer pointed at the new game:

    ```bash
    cd /home/pi/CreationStationArcade
    sudo bash install/single-native-arcade-setup.sh --game=NewName
    sudo reboot
    ```

    !!! note "What this does"
        Updates the auto-launch settings to boot into the new game, then reboots into it.

## Putting a new game on the arcade

1. Build the native binary in the `make-web` `/desktop` tool (Step 1), choosing the right architecture (`arm64` for a Pi, `x86-64` for a PC).
2. Copy the `.tar.gz` onto the Pi and extract it into `games/<Name>/` (Step 5).
3. Re-run the installer with `--game=<Name>` and reboot (above).

You can also save the new game folder to the project and upload it through git to keep the source of truth in the repo.

## If something goes wrong

### The screen is black with a cursor, or "SDL Error: Invalid window"

This means the graphics setup is incomplete. The `Game` binary needs the OpenGL ES renderer explicitly. The installer sets `SDL_RENDER_DRIVER=opengles2` for you, but if it's missing you'll see a black window. Make sure you ran the installer (it sets this), and on a Pi make sure the `vc4-kms-v3d,cma-128` overlay is enabled in your boot config (the installer does this too). Re-run the installer to rewrite both.

!!! note "Why this happens"
        Without `SDL_RENDER_DRIVER=opengles2` the window opens but stays black. Without the EGL/GLES libraries (`libegl1`, `libgles2`) the window can fail to create at all. The installer installs all of these, so re-running it fixes both.

### "no native game found" during setup

The installer looks for a folder under `games/` that contains **both** `Game` and `libpxt.so`. If it can't find one, check:

```bash
ls -l /home/pi/CreationStationArcade/games/MyGame/
```

!!! note "What this does"
        Lists the files in your game folder. You should see both `Game` and `libpxt.so`. If `Game` isn't marked executable, run `chmod +x games/MyGame/Game`. If a file is missing, re-extract the archive (Step 5).

### I'm on a 32-bit Pi (original Pi Zero / Pi 1)

The `Game` binary is 64-bit only (`aarch64`). It will not run on a 32-bit OS. Install a 64-bit OS, or pick a different flavor (the [Pi 3 / Pi Zero Single-Game ELF](pi3-elf-kiosk.md) works on the original Pi Zero).

### No HDMI audio

This flavor includes the HDMI audio fix. Run it and reboot:

```bash
sudo /home/pi/CreationStationArcade/install/hdmi-audio-fix.sh
sudo reboot
```

!!! note "What this does"
        Copies in corrected HDMI audio settings and backs up your old ones. Reboot so they load.

### I need to get back to a normal prompt

The auto-launch runs on TTY1. To disable it for debugging, use the toggle script that comes with this branch:

```bash
bash /home/pi/CreationStationArcade/toggle-arcade.sh disable
```

!!! note "What this does"
        Turns off the auto-launch so the next time you log in on TTY1 you get a normal shell instead of the game. Re-enable it with `toggle-arcade.sh enable` when you're done. See the project's `notes.md` for more.

### I need to kill a stuck game from another session

Log in as an admin user (or over SSH) and run:

```bash
sudo pkill -9 -f "games/[^/]+/Game"
sudo pkill -9 -f launcher.sh
```

!!! note "What this does"
        Force-stops any running `Game` process and the launcher loop. Then see `notes.md` for restoring the launcher shell.
