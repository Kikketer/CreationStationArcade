# Pi 3 / Pi Zero Single-Game ELF

## What this is / who it's for

This is the **single-game** ELF flavor. There's no menu — the cabinet boots straight into one configured `.elf` game and a reset button restarts that same game. It's the simplest, lightest arcade.

It's the best choice if you:

- Have a **Raspberry Pi 3** or a **Pi Zero / Zero 2 W** (the raw ELF is built for ARMv6 / BCM2835, so it runs on both).
- Want a dedicated cabinet for **one** game.
- Are okay using raw `.elf` files exported from MakeCode Arcade.

!!! tip "Want a menu of games instead?"
        If you'd rather have a list of games to pick from on a Pi 3, use the [ELF Menu Arcade](elf-menu.md) guide.

!!! note "About the Pi Zero"
        The Pi Zero has only **one USB port**. If you plug a wired USB gamepad into it, that port is busy, so you can't also use the USB-drive/gadget feature at the same time. Use a **Pi Zero W** with Wi-Fi to transfer games, or move the SD card. The Zero is also slower than the Pi 3 (single-core 1 GHz, 512 MB RAM), so boots and restarts take longer.

## What you'll need

**Hardware**

- A **Raspberry Pi 3** or **Pi Zero / Zero 2 W**.
- A microSD card (16 GB or bigger).
- A power supply for the Pi.
- An HDMI screen.
- A **USB gamepad** (recommended), OR arcade buttons wired to the Pi's GPIO pins (only for the 4-player raw ELF fork — see the input modes note below).
- A way to put the microSD card into your regular computer.
- An internet connection for the Pi (Wi-Fi or Ethernet; Wi-Fi only on the Pi Zero W).

**On your regular computer**

- A web browser (to download the OS and to make games in MakeCode Arcade).

## The walkthrough

### Step 1 — Flash the operating system

This flavor needs the **32-bit Lite** version of Raspberry Pi OS.

1. On your regular computer, download **Raspberry Pi Imager** from <https://www.raspberrypi.com/software/>.
2. Put the microSD card into your computer.
3. Open Raspberry Pi Imager.
4. Under **Choose OS**, pick **Raspberry Pi OS (Other)** → **Raspberry Pi OS Lite (32-bit)**. (Trixie was the last version tested.)
5. Under **Choose Storage**, pick your microSD card.
6. Click **Write** and wait for it to finish.

!!! note "What this does"
        Copies a fresh, minimal (no desktop) operating system onto the SD card.

### Step 2 — Boot the Pi and get it online

1. Put the SD card into the Pi, plug in the HDMI screen, and power it on.
2. Log in when prompted:

    - Username: `pi`
    - Password: `raspberry`

3. If you're using Wi-Fi, connect with:

    ```bash
    sudo raspi-config
    ```

    !!! note "What this does"
            Opens the Pi's settings menu. Go to **System Options → Wireless LAN**, pick your country, type your Wi-Fi name and password, then finish.

4. Check the connection:

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
        Installs `git`, the program that copies code projects from the internet onto your Pi.

### Step 4 — Download the arcade project

```bash
git clone -b pi3-elf-kiosk https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src
```

!!! note "What this does"
        Copies the Creation Station Arcade project into a folder called `CreationStationArcade-src`. The `-b pi3-elf-kiosk` part grabs the single-game ELF flavor specifically.

### Step 5 — Run the one-shot setup script

This flavor has a single setup script that does almost everything: installs packages, sets up auto-login, makes the game and scripts runnable, writes the auto-launch settings, installs the reset-button monitor, and hides the boot text.

```bash
bash /home/pi/CreationStationArcade-src/install/pi3-elf-setup.sh --game=AndyPaddleTheRiver
```

!!! note "What this does"
        The all-in-one installer for this flavor. Replace `AndyPaddleTheRiver` with the name of any `.elf` file that's in the project's `games/` folder (use the name **without** the `.elf`). The script will tell you which games are available if you give it a name it can't find.

!!! tip "Which input mode?"
        By default the script uses **keyboard mode** — your USB gamepad is translated into a virtual keyboard, which is what the standard MakeCode Arcade raw ELF expects.

        If you're using the **4-player raw ELF fork** (the one that reads GPIO pins instead of keyboard events), add `--input-mode=gpio`:

        ```bash
        bash /home/pi/CreationStationArcade-src/install/pi3-elf-setup.sh --game=YourGame --input-mode=gpio
        ```

        !!! note "What this does"
                Tells the setup to wire the USB gamepad to the Pi's GPIO pins instead of a virtual keyboard. Only use this with the 4-player raw ELF fork.

### Step 6 — Install the boot splash screen (hides boot text)

```bash
sudo /home/pi/CreationStationArcade/install/splash-setup.sh
sudo reboot
```

!!! note "What this does"
        Installs a tiny image viewer (`fbi`), turns on a service that shows the arcade logo during boot, and edits the boot settings to hide the scrolling kernel text. Log back in as `pi` / `raspberry` after the reboot.

### Step 7 — (Only if games have no sound) Fix HDMI audio

```bash
sudo /home/pi/CreationStationArcade/install/hdmi-audio-fix.sh
sudo reboot
```

!!! note "What this does"
        Copies in corrected HDMI audio settings and backs up your old ones. Reboot so they load. Skip this if your games already have sound.

### Step 8 — Reboot and play

After the reboot, the Pi should auto-log in as `pi` and launch your game. Plug in your USB gamepad and play. The reset button (or the reset service) restarts the same game.

## Changing the game later

To switch to a different game, just re-run the setup script with a new `--game` name and reboot:

```bash
bash /home/pi/CreationStationArcade-src/install/pi3-elf-setup.sh --game=YourOtherGame
sudo reboot
```

!!! note "What this does"
        Re-runs the installer pointed at a different game. It updates the auto-launch settings and the reset-button service to use the new game name, then the reboot starts it.

To see which games are available:

```bash
ls /home/pi/CreationStationArcade-src/games/*.elf
```

!!! note "What this does"
        Lists every `.elf` file in the games folder. Use the file name **without** the `.elf` part as the `--game` value.

## Putting a new game on the arcade

1. Open your game in the MakeCode Arcade editor in your browser.
2. Add this to the **end of the web address**:

    ```
    ?nolocalhost=1&compile=rawELF&hw=rpi#editor
    ```

    !!! note "What this does"
            Turns on the hidden "raw ELF" export for the Raspberry Pi hardware.

3. Click **Download** (bottom-left) to get a `.elf` file.
4. Copy that `.elf` file into the project's `games/` folder (on the Pi as `pi` or `admin`, or by pushing it through git).
5. Re-run the setup script with the new game name (see *Changing the game later* above) and reboot.

## If something goes wrong

### The "Hardware" line gotcha (the big one)

The raw `.elf` game needs the Pi to report a line called `Hardware` about itself. The Pi 3 and Pi Zero still include this line; **the Pi 5 removed it**, which is why this flavor only works on a Pi 3 or Pi Zero.

The setup script checks for the line and warns you if it's missing. The danger is the same as the menu flavor: **don't run `sudo apt upgrade`**, because a newer kernel can delete the `Hardware` line and your game will stop launching.

!!! warning "Do not run `sudo apt upgrade` on this arcade"
        The setup script deliberately skips the full upgrade to protect the kernel version. To check whether your Pi still has the line:

        ```bash
        grep Hardware /proc/cpuinfo
        ```

        !!! note "What this does"
                Prints the `Hardware` line. You want to see `Hardware : BCM2835`. If nothing prints, the line is gone and the ELF won't run. Back up your working SD card image once the arcade runs, so you can re-flash it if the kernel ever updates by accident.

### Pi Zero: only one USB port

If you plug a wired USB gamepad into the Pi Zero, the single USB port is in "host" mode, so you can't also use the USB-drive/gadget feature. Transfer games over Wi-Fi (Pi Zero W) or by moving the SD card.

### No HDMI audio

Run the HDMI audio fix from Step 7 and reboot.

### The reset button doesn't restart the game

The reset button is handled by a background service called `arcade-monitor`. Check it's running:

```bash
sudo systemctl status arcade-monitor.service
```

!!! note "What this does"
        Shows whether the reset-button monitor service is running. If it says "failed" or "inactive", try `sudo systemctl restart arcade-monitor.service`. A reboot will also start it.

### The game doesn't launch on boot

The auto-launch settings live in `~/.bash_profile` and `~/.profile`. If they got removed, re-run the setup script from Step 5 — it rewrites them.

### I need a normal prompt to fix something

The `pi` user auto-launches the game on TTY1. To get a normal shell, log in over a different path (for example, plug in a USB keyboard and switch to a second virtual terminal with `Ctrl+Alt+F2`), or SSH in if you enabled it. From there you can re-run the setup script or edit files.
