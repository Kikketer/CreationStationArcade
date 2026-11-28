# Guided Installer

The guided installer is the easiest way to build a Creation Station Arcade. It detects the computer inside your cabinet, asks a few plain questions, recommends the right arcade flavor, and runs the correct branch installer behind the scenes.

You do **not** need to know which branch to use.

## Before you start

The installer does not flash or install the operating system. Start with a machine that already has:

- Raspberry Pi OS Lite, Debian, or Ubuntu installed.
- An internet connection.
- A normal user account with `sudo` access.
- For Raspberry Pi ELF/Chromium flavors, a user named `pi` — several older branch installers still assume that account.

Use the operating-system instructions in the flavor guides if you are not sure which OS image to pick.


!!! danger "Dedicated machine required"
    Use this only on an empty machine or fresh OS install that will become a dedicated arcade cabinet. The installer changes boot behavior, autologin, packages, device rules, and startup services. It is not for a machine you use for everyday work or personal files.

## Run it

Log in as the arcade user and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Kikketer/CreationStationArcade/main/install.sh | bash
```

Do **not** put `sudo` in front of it. The installer runs as the arcade user and asks for administrator access only when it needs to install packages or change boot settings.

## What it asks

The exact questions depend on the machine. Usually you will see:

1. **Cabinet report** — confirms the detected machine, operating system, architecture, and user.
2. **Engine choice** — Chromium or Native where both are possible. ELF is chosen automatically on the Pi models that support it.
3. **Cabinet style** — a menu of games or one dedicated game.
4. **Controls** — USB controllers or GPIO-wired arcade buttons on a Raspberry Pi.
5. **Game selection** — for single-game flavors, the installer lists the games included in that branch and lets you pick one.
6. **Build sheet** — a final confirmation before changing the system.

Long operations show a spinner and write details to `~/creation-station-installer.log`.

## Native cabinets need game archives first

Native flavors do not include game binaries in the repository. Before installing, build your games with the [PNG to Desktop compiler](https://www.makecode.games/compilers/desktop).

The installer accepts:

- one `.tar.gz` file already copied to the arcade machine;
- a folder containing several `.tar.gz` files;
- an `http://` or `https://` URL for one archive.

For a native **menu** cabinet, include the compiled menu project. It must install as `games/Menu/` or the cabinet cannot show the menu.

## What it chooses

| Detected machine | Menu choice | Single-game choice |
| --- | --- | --- |
| Pi 3, 32-bit OS | ELF menu | Single-game ELF |
| Pi Zero / Zero 2 W, 32-bit OS | — | Single-game ELF |
| Pi 5, 64-bit OS | Chromium menu (recommended) or Native | Chromium single-game (recommended) or Native |
| Pi 3/4/Zero 2 W, 64-bit OS | Native menu | Native single-game |
| x86-64 Debian/Ubuntu PC | Chromium menu (recommended) or Native | Chromium single-game (recommended) or Native |

The branches still exist, but they are implementation details. The installer uses `main`, `pi3-elf-kiosk`, `chromium-kiosk`, `single-game-kiosk`, `single-native-arcade`, or `multi-native-arcade` as needed.

## Preview without changing anything

```bash
curl -fsSL https://raw.githubusercontent.com/Kikketer/CreationStationArcade/main/install.sh -o /tmp/arcade-install.sh
bash /tmp/arcade-install.sh --dry-run
```

The dry run stops after the build sheet, before cloning or changing system configuration. You can also inspect the downloaded file first with `less /tmp/arcade-install.sh`.

## After installation

The installer asks whether to reboot. If you answer no, reboot later with:

```bash
sudo reboot
```

Useful files after installation:

- Installer log: `~/creation-station-installer.log`
- Branch installer log: usually `~/arcade-setup.log` or `~/arcade.log`
- Source checkout: usually `~/CreationStationArcade-src` for ELF/Chromium flavors or `~/CreationStationArcade` for Native flavors


## USB controller calibration

For Chromium and Native cabinets that use USB controls, the installer offers a guided calibration step after the system install. It prompts for each player and each control:

- up, down, left, right
- A and B
- reset/exit

Press `Esc` to skip one control or `f` to finish early. This means a one-player cabinet does not have to step through controls for extra players.

The wizard writes `/etc/arcade-controller-map.json` and enables the `arcade-input-remap` systemd service. The service reads the configured physical inputs exclusively and creates a virtual keyboard named `Creation Station Calibrated Input` (also linked at `/dev/input/arcade-calibrated` when the system allows it). It emits the standard MakeCode keyboard controls: player 1 uses `WASD` + `Q/E`, player 2 uses `IJKL` + `U/O`; player 1 also emits the Chromium menu's arrow-key and `Z/X` aliases.

The first version of this calibration layer supports one or two players because those are the keyboard-player assignments MakeCode defines. Three- and four-player cabinets should use standard gamepads or GPIO wiring for the additional players until virtual-gamepad remapping is added and hardware-tested.

!!! warning "Calibration grabs the selected input device"
    Do not calibrate using the keyboard you still need to administer the machine. Once the service starts, calibrated devices are grabbed for arcade input. Use the real cabinet buttons/encoder, or stop `arcade-input-remap.service` if you need the device back.

## Current limits

- Raspberry Pi ELF and Chromium installers still expect the `pi` user. The single-game Chromium branch also expects `pi` on x86 because its runtime paths are still hard-coded. The installer stops with a clear message if another user selects one of those flavors.
- ELF games require the legacy `Hardware` line in `/proc/cpuinfo`. The installer checks it and warns before continuing.
- The installer cannot flash the OS, physically wire controls, or compile games for you.
- Native support depends on archives built for the correct architecture: `arm64` for 64-bit Pi boards, `x86-64` for PCs.
- USB controller setup maps physical USB ports to stable player numbers. The optional calibration wizard additionally translates cabinet inputs into MakeCode keyboard controls for one or two players. MakeCode games own their logical button meanings; this is cabinet input alignment, not per-game remapping.
