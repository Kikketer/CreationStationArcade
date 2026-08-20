# ELF Menu Arcade

## What this is / who it's for

This is the **menu** flavor of Creation Station Arcade. It boots into a menu of games (the menu itself is a MakeCode Arcade game called `MadeArcadeMenu.elf`), and you pick a game from the list to play. It runs raw `.elf` files — the "close to what MakeCode intended" path for the ELF arcades.

It's the best choice if you:

- Have a **Raspberry Pi 3** (this is the only modern Pi it runs on — see the gotcha below).
- Want more than one game available on the cabinet.
- Are okay using raw `.elf` files exported from MakeCode Arcade.

!!! tip "One game, not a menu?"
        If you'd rather boot straight into a single game with no menu, use the [Pi 3 / Pi Zero Single-Game ELF](pi3-elf-kiosk.md) guide instead. It's simpler.

## What you'll need

**Hardware**

- A **Raspberry Pi 3** (Model B or B+). The Pi 5 does **not** work for this flavor.
- A microSD card (16 GB or bigger is plenty).
- A power supply for the Pi.
- An HDMI screen (a TV or monitor).
- A **USB gamepad**, OR arcade buttons wired to the Pi's GPIO pins (for up to 4 players).
- A way to put the microSD card into your regular computer (a USB adapter or built-in slot).
- An internet connection for the Pi (Wi-Fi or Ethernet).

**On your regular computer**

- A web browser (to download the OS and to make games in MakeCode Arcade).

## The walkthrough

### Step 1 — Flash the operating system onto the SD card

This flavor needs the **32-bit Lite** version of Raspberry Pi OS. "Lite" means no desktop — the Pi boots straight to a text screen, which is what we want for an arcade.

1. On your regular computer, download the **Raspberry Pi Imager** from <https://www.raspberrypi.com/software/>.
2. Put the microSD card into your computer.
3. Open Raspberry Pi Imager.
4. Under **Choose OS**, pick **Raspberry Pi OS (Other)** → **Raspberry Pi OS Lite (32-bit)**. (Trixie was the last version tested.)
5. Under **Choose Storage**, pick your microSD card.
6. Click **Write**. Wait for it to finish.

**What this does** — It copies a fresh, minimal operating system onto the SD card. The Pi will boot from this card.

### Step 2 — Boot the Pi and connect it to the internet

1. Put the SD card into the Pi.
2. Plug the Pi into your screen (HDMI) and power it on.
3. When it finishes booting, you'll see a login prompt. Log in with:

    - Username: `pi`
    - Password: `raspberry`

4. If you're using Wi-Fi, connect the Pi to your network. The easiest way is to run:

    ```bash
    sudo raspi-config
    ```

    **What this does** — Opens the Pi's settings menu. Use your arrow keys to go to **System Options → Wireless LAN**, pick your country, type your Wi-Fi name and password, then finish.

5. Make sure the Pi is online by running:

    ```bash
    ping -c 3 google.com
    ```

    **What this does** — Sends three test messages to the internet. If you see replies, the Pi is online. Press `Ctrl+C` if it doesn't stop on its own.

### Step 3 — Install the tool that downloads the arcade software

The Pi needs a small program called `git` to download the arcade files from the internet.

```bash
sudo apt install git
```

**What this does** — Installs `git`, the program that copies code projects from the internet onto your Pi. Type `y` if it asks to confirm.

### Step 4 — Download the arcade project

```bash
git clone https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src
```

**What this does** — Copies the entire Creation Station Arcade project into a folder called `CreationStationArcade-src` inside your home folder. The `-src` at the end matters — the next step depends on it.

### Step 5 — Create the runtime folder

This flavor uses **two folders**:

- `/home/pi/CreationStationArcade-src` — the "source" copy. It can be updated in the background and is never running while you play.
- `/home/pi/CreationStationArcade` — the "runtime" copy. The arcade actually runs from here.

```bash
bash /home/pi/CreationStationArcade-src/setup.sh
```

**What this does** — Creates the runtime folder (`CreationStationArcade` — without the `-src`) and copies the project files into it. The `setup.sh` script checks that you ran it from the `-src` folder and refuses if you didn't.

### Step 6 — Install the boot splash screen (hides the boot text)

By default the Pi prints a bunch of scrolling text while it starts up. This step replaces that with the arcade logo so the cabinet looks clean.

```bash
sudo /home/pi/CreationStationArcade/install/splash-setup.sh
sudo reboot
```

**What this does** — The first command installs a tiny image viewer (`fbi`), turns on a background service that shows the arcade logo, and edits the Pi's boot settings so the kernel text is hidden. The second command restarts the Pi so the changes take effect. Log back in as `pi` / `raspberry` after it reboots.

### Step 7 — (Only if games have no sound) Fix HDMI audio

If your games have no sound over HDMI, run this and reboot:

```bash
sudo /home/pi/CreationStationArcade/install/hdmi-audio-fix.sh
sudo reboot
```

**What this does** — Copies in corrected audio settings for the Pi's HDMI output and backs up your old ones. Reboot so the new settings load. (You can skip this step if your games already have sound.)

### Step 8 — Create an "admin" user

You'll make a second user account just for managing the machine, so the `pi` account can stay locked to the arcade.

```bash
sudo adduser admin
sudo usermod -aG sudo admin
```

**What this does** — Creates a new user called `admin` and gives it permission to run administrator commands. It'll ask you to set a password for `admin` — pick one you'll remember.

### Step 9 — Set up shared file permissions

So both `pi` and `admin` can edit the arcade's files without stepping on each other, you'll create a shared group.

```bash
sudo groupadd arcadeadmin
sudo usermod -aG arcadeadmin pi
sudo usermod -aG arcadeadmin admin
sudo chgrp -R arcadeadmin /home/pi
sudo find /home/pi -type d -exec chmod 2770 {} \;
sudo find /home/pi -type f -exec chmod 660 {} \;
echo "umask 002" | sudo tee /etc/profile.d/arcadeadmin.sh
source /etc/profile.d/arcadeadmin.sh
```

**What this does** — Makes a group called `arcadeadmin`, adds both users to it, sets the home folder so any new files are automatically shared between them, and sets a default rule so future files keep those shared permissions.

### Step 10 — (Optional) Set up a custom menu folder

If you want the menu to list and launch games from a special folder (instead of the default `games/` folder), make it now:

```bash
sudo mkdir -p /sd/prj
sudo chmod +w /sd/prj
```

**What this does** — Creates a folder at `/sd/prj` that the custom menu will read from. Skip this if you're happy with the default games folder.

### Step 11 — Lock the `pi` user to the arcade

The last setup step makes the `pi` user boot straight into the arcade instead of a normal text shell.

```bash
sudo usermod -s /home/pi/CreationStationArcade/launcher.sh pi
```

**What this does** — Changes the `pi` user's "login shell" — the program that runs when `pi` logs in — to the arcade's `launcher.sh` script. From now on, whenever the Pi boots and auto-logs in as `pi`, it goes straight into the arcade loop.

### Step 12 — Reboot and play

```bash
sudo reboot
```

When the Pi comes back up, it should show the arcade logo during boot and then drop you into the game menu. Plug in your USB gamepad (or use your wired GPIO buttons) and play.

## Putting games on the arcade

### Simple addition (1–2 players)

If you don't need 4 players, you can export a regular raw `.elf` from MakeCode Arcade.

1. Open your game in the MakeCode Arcade editor in your browser.
2. Add this to the **end of the web address** (the URL in the address bar):

    ```
    ?nolocalhost=1&compile=rawELF&hw=rpi#editor
    ```

    **What this does** — Tells MakeCode to show the hidden "raw ELF" export option for the Raspberry Pi hardware.

3. Click the **Download** button (bottom-left). You'll get a `.elf` file.
4. Put that `.elf` file into the `games/` folder of the arcade project (on the `pi` or `admin` account, or by pushing it through git).
5. Save the change to the project and upload it (the next section explains the two-reboot flow).

### 4-player games

4-player games aren't officially supported by MakeCode Arcade, so you have to build the `.elf` yourself using the 4-player raw ELF fork. See the project's `readme.md` for the full pxt setup. The short version: you check out the `feat-raw-elf-four-player` branches of the `pxt` and `pxt-arcade` forks, run `npm serve`, import your game, pick **Pi0 Raw Elf** as the hardware, and download the resulting `.elf`. Drop it into `games/` and update `launcher.sh` to point at it.

### The two-reboot update flow

When you add or change a game and upload it to the project, the arcade doesn't pick it up instantly. It works like this:

1. **First reboot:** the source folder (`*-src`) downloads the latest project files from the internet in the background.
2. **Second reboot:** the launcher copies the new files from the source folder into the runtime folder and runs them.

So after you push a new game: reboot once (wait for it to finish), then reboot again. Your new game will appear.

!!! note "Why two reboots?"
        The arcade runs from the runtime folder, but only the source folder talks to the internet. The first reboot refreshes the source; the second copies source → runtime. This keeps a half-downloaded update from breaking the game you're currently playing.

## If something goes wrong

### The Pi 3 "Hardware" line gotcha (the big one)

The raw `.elf` games need the Pi to report a line called `Hardware` about itself. The Pi 3's current software still includes that line. **The Pi 5's software removed it**, which is why this flavor only works on a Pi 3.

The danger: if you run the normal "update everything" command on your Pi 3, it can pull down the newer kernel that deletes the `Hardware` line, and your arcade will stop booting.

!!! warning "Do not run `sudo apt upgrade` on this arcade"
        The setup scripts in this project deliberately skip the full upgrade to protect the kernel version. If you ever run `sudo apt upgrade` (or accept a prompt that upgrades the kernel), the `Hardware` line may disappear and the ELF games will fail to launch.

        To check whether your Pi still has the line:

        ```bash
        grep Hardware /proc/cpuinfo
        ```

        **What this does** — Prints the `Hardware` line from the Pi's CPU info. You want to see `Hardware : BCM2835`. If nothing prints, the line is gone and the ELF games won't run.

        **Back up your working SD card image** once the arcade is running, so if the kernel ever updates by accident you can re-flash the good version.

### No HDMI audio

Run the HDMI audio fix from Step 7 and reboot. If it still doesn't work, check that your screen/TV is set to use HDMI audio and the volume isn't muted.

### GPIO buttons don't work on a Pi 5

They won't — `wiringPi`, the library this flavor uses to talk to the GPIO pins, is dead on the Pi 5. Use a USB gamepad or a USB zero-delay encoder instead, or switch to a [Chromium](chromium-kiosk.md) or [Native](single-native-arcade.md) flavor.

### The arcade boots to a text prompt instead of the menu

The `pi` user's login shell probably got reset. Re-run Step 11:

```bash
sudo usermod -s /home/pi/CreationStationArcade/launcher.sh pi
```

then reboot.

### I need to get back to a normal prompt to fix something

Log in as the `admin` user (from Step 8) instead of `pi`. The `admin` account has a normal shell, so you can run commands and fix things. To temporarily give `pi` a normal shell again:

```bash
sudo usermod -s /bin/bash pi
```

**What this does** — Switches the `pi` user back to a normal text shell so you can log in and troubleshoot. Re-run Step 11 to lock it back to the arcade when you're done.
