# Creation Station Arcade - Single Game Kiosk Mode

This branch provides a simplified arcade setup that launches directly to a single game instead of showing a menu. Perfect for dedicated arcade cabinets running one specific game.

## Key Features

- **Direct game launch** - No menu, boots straight to the configured game
- **Game restart on reset** - Reset button restarts the current game instantly
- **Full USB controller support** - Works with both GPIO buttons and USB controllers
- **Simplified architecture** - Single Chromium instance, optimized for performance
- **Easy configuration** - Set your game via environment variable

## Quick Setup

### 1. Install Base System

Follow the standard Raspberry Pi setup:
```bash
# Install 32-bit Lite Raspberry Pi OS
sudo apt install git
git clone https://github.com/kikketer/CreationStationArcade /home/pi/CreationStationArcade-src
bash /home/pi/CreationStationArcade-src/setup.sh
```

### 2. Configure Single Game Mode

```bash
# Switch to single-game branch
cd /home/pi/CreationStationArcade-src
git checkout single-game-kiosk

# Set your game (optional, defaults to AndyPaddleTheRiver)
export SINGLE_GAME_NAME="ChrisVikingsOfFour"

# Install single-game services
sudo systemctl stop gpio-monitor
sudo systemctl disable gpio-monitor
sudo cp gpio-monitor-single-game.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gpio-monitor-single-game
sudo systemctl start gpio-monitor-single-game

# Ensure USB controller support
sudo systemctl enable gpio-gamepad
sudo systemctl start gpio-gamepad

# Set up USB controllers (if using USB gamepads)
sudo ./setup-usb-controllers.sh
```

### 3. Update Autostart

Edit `/etc/xdg/openbox/autostart` to use the single-game launcher:
```bash
# Comment out standard launcher
# /home/pi/CreationStationArcade/launcher.sh &

# Use single-game launcher
/home/pi/CreationStationArcade/single-game-launcher.sh &
```

### 4. Set User Login

```bash
# Set pi user to auto-launch single-game mode
sudo usermod -s /home/pi/CreationStationArcade/single-game-launcher.sh pi
```

## Available Games

Configure your game by setting `SINGLE_GAME_NAME`:

- `AndyPaddleTheRiver` - Paddle The River (1 player)
- `ChrisGreedyPirates` - Greedy Pirates (2 players)  
- `ChrisVikingsOfFour` - Vikings Of Four (4 players)
- `EliSonicMiniboss` - Sonic Miniboss (1 player)
- `EliSuperStarStory` - Super Star Story (4 players)
- `EvelynBunnyCat` - Bunny Cat (1 player)
- `KaitoBubbleSlash` - Bubble Slash (1 player)
- `LucianCave` - Cave (2 players)
- `RiojiCat` - Cat (1 player)
- `ScottSaveYourself` - Save Yourself (1 player)
- `WilliamDoubleDeath` - Double Death (1 player)
- `WilliamZombie` - Zombie (2 players)

## Controller Support

### USB Controllers
```bash
# Set up stable controller mapping by USB port
sudo ./setup-usb-controllers.sh
```

### GPIO Buttons
- Works via virtual USB gamepads (gpio-gamepad.py)
- Same pin mapping as standard mode
- Reset button (GPIO 4) restarts the game

## Button Behavior

- **Reset Button (GPIO 4)** - Restarts the current game
- **Game Controls** - Work normally for the selected game
- **USB Controllers** - Fully supported via gpio-gamepad service
- **GPIO Buttons** - Work via virtual USB gamepads

## Reset Button Function

When pressed, the reset button:
1. Kills the current game instance
2. Restarts the gamepad service (fixes controller issues)
3. Syncs latest code updates
4. Relaunches the same game
5. Re-applies window focus

This provides instant game restart without rebooting the entire system.

## Troubleshooting

### Game Won't Start
```bash
# Check game name spelling
cat /home/pi/arcade.log | tail -20

# Verify game file exists
ls /home/pi/CreationStationArcade/games/YourGameName.js
```

### Reset Button Not Working
```bash
# Check GPIO monitor service
sudo systemctl status gpio-monitor-single-game

# Check service logs
sudo journalctl -u gpio-monitor-single-game -f
```

### USB Controllers Not Working
```bash
# Check gamepad service
sudo systemctl status gpio-gamepad

# Check detected controllers
ls /dev/input/js*

# Check gamepad logs
sudo journalctl -u gpio-gamepad -f
```

## File Structure

- `single-game-launcher.sh` - Main launcher (replaces launcher.sh)
- `reset-single-game.sh` - Reset handler for game restart
- `gpio-monitor-single-game.py` - Simplified GPIO monitor
- `gpio-monitor-single-game.service` - Systemd service
- `SINGLE_GAME_README.md` - Detailed documentation

## Switching Back to Menu Mode

```bash
# Restore standard services
sudo systemctl stop gpio-monitor-single-game
sudo systemctl disable gpio-monitor-single-game
sudo systemctl enable gpio-monitor
sudo systemctl start gpio-monitor

# Switch back to main branch
cd /home/pi/CreationStationArcade-src
git checkout chromium-kiosk

# Update autostart to use standard launcher
# Edit /etc/xdg/openbox/autostart to use launcher.sh
```

## Performance

This mode is optimized for single-game performance:
- Single Chromium instance (lower memory usage)
- No menu overhead (faster boot)
- Simplified GPIO monitoring (less CPU usage)
- Direct game URL loading (faster startup)

## Testing

Run the test script to verify setup:
```bash
./test-single-game.sh
```

---

**Base System Setup:** For complete Raspberry Pi setup, user management, and game development details, see the standard setup documentation.

## Folder layout

- `/home/pi/CreationStationArcade-src`
  - Source repo (git)
  - Can be updated in the background and is not actively running
- `/home/pi/CreationStationArcade`
  - Runtime folder
  - On boot, `launcher.sh` syncs from `*-src` to this folder and then runs from here

## Putting Games On The Arcade

### Simple Addition

If you don't need to use all 4 players you can simply export your game as a raw elf from the standard MakeCode Arcade interface. Raw elf is hidden and really crossing my fingers they don't remove this feature, but maybe if you promote my post and github fork we'd be able to get it built in for real! https://forum.makecode.com/t/4-player-gpio-raw-elf-export/41383

1. Put `?nolocalhost=1&compile=rawELF&hw=rpi#editor` on the end of the url.
2. Load the game you wish to add to the arcade
3. Click the "download" button on the bottom left
4. You'll then have a `.elf` file downloaded
5. Move this file to the CreationStationArcade/gaems directory
6. Commit and push the repo
7. The arcade will pull and copy over the next time it boots, it'll take two reboots (one to download, and one to copy over).

### 4 Player Option

4 Player games are not officially supported by MakeCode Arcade (even though the "cardboard" setup has the pin layout). So if you need to build a game for the 4 player controllers you need to do it manually and locally.

1. Setup the pxt, pxt-arcade, and pxt-common-packages repos from my forks (this is a little painful but you got this). I put everything in a single folder called `pxt-root`.
   - https://github.com/Kikketer/pxt/tree/kikketer/feat-raw-elf-four-player
   - https://github.com/Kikketer/pxt-arcade/tree/kikketer/feat-raw-elf-four-player
   - https://github.com/Kikketer/pxt-common-packages/tree/master
2. There's an npm link step here... trying to remember how to do it, it was finicky at best
3. Once you have all the repos checked into that single `pxt-root` folder be sure to check out the "feat-raw-elf-four-player" branches of the pxt and pxt-arcade projects.
4. Navigate to `pxt-arcade` and run `npm serve`
5. A local copy will start, now you just need to import the game you wish to put on the arcade.
6. Once you have the game loaded, pick the "choose hardware" near the download button
7. Pick "Pi0 Raw Elf" option
8. Click download
9. Now you have a 4 player .elf file that can be used on the arcade, copy this into the `CreationStationArcade/games` folder
10. Update the `launcher.sh` to point to your new game name
11. Commit and push
12. Then reboot the arcade box, it'll pull on the first reboot, reboot again and it'll copy over the new one (yes that's 2 reboots)

## Known Issues

- Raspberry PI 3 is the only modern device that works due to "Hardweare" line needed in the `/proc/cpuinfo` which is generally useless but the ELF files demand it to be there.

> The Pi 3 works because it still ships a slightly older 6.x kernel point-release that still contains the “Hardware” line.
> The Pi 5 image you flashed already carries a newer 6.x point-release in which the Raspberry Pi Foundation deliberately deleted that line (they got tired of every Pi reporting BCM2835 and confusing users).
> So on the Pi 5 the ELF aborts, while on the Pi 3 it starts—even though both run the same 32-bit Trixie Lite OS.
> Once your Pi 3 updates to the same kernel revision as the Pi 5, it will also lose the line and fail in exactly the same way.

BTW that sounds like a horrible day, so let's get a copy of that OS and keep it forever.

- `wiringPi` is dead on Raspberry Pi 5

This means that the GPIO is basically useless and can't be used for the gaming machine.
