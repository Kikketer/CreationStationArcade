# Single Game Kiosk Mode

This branch provides a simplified arcade setup that launches directly to a single game instead of showing a menu. When the reset button is pressed, the game restarts instead of returning to a menu.

## Key Differences from Standard Mode

- **No menu system** - launches directly to the configured game
- **Reset button restarts the game** instead of returning to menu
- **Simplified GPIO monitoring** - only handles reset functionality
- **Single Chromium instance** - no dual-window management

## Configuration

### Setting the Game

Edit the `GAME_NAME` variable in `single-game-launcher.sh` (line 18):

```bash
# CONFIGURE YOUR GAME HERE - set to the game file name (without .js extension)
# Examples: "AndyPaddleTheRiver", "ChrisGreedyPirates", "ChrisVikingsOfFour", etc.
GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}"
```

Or set the environment variable:
```bash
export SINGLE_GAME_NAME="ChrisGreedyPirates"
```

### Available Games

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

## Setup Instructions

### 1. Install the Service

Replace the standard GPIO monitor with the single-game version:

```bash
# Stop and disable the standard service
sudo systemctl stop gpio-monitor
sudo systemctl disable gpio-monitor

# Install the single-game service
sudo cp gpio-monitor-single-game.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gpio-monitor-single-game
sudo systemctl start gpio-monitor-single-game
```

### 2. Update Autostart

Modify your autostart configuration to use `single-game-launcher.sh` instead of `launcher.sh` or `dual-chromium-launcher.sh`.

For example, in `/etc/xdg/openbox/autostart`:
```bash
# Comment out the standard launcher
# /home/pi/CreationStationArcade/launcher.sh &

# Use the single-game launcher
/home/pi/CreationStationArcade/single-game-launcher.sh &
```

### 3. Configure Game (Optional)

Set your preferred game by editing the launcher script or setting the environment variable:

```bash
# Method 1: Edit the script
nano single-game-launcher.sh
# Change GAME_NAME="${SINGLE_GAME_NAME:-AndyPaddleTheRiver}" to your preferred game

# Method 2: Set environment variable
export SINGLE_GAME_NAME="ChrisVikingsOfFour"
```

## File Structure

- `single-game-launcher.sh` - Main launcher script (replaces launcher.sh)
- `reset-single-game.sh` - Reset handler that restarts the game
- `gpio-monitor-single-game.py` - Simplified GPIO monitor for reset button
- `gpio-monitor-single-game.service` - Systemd service file

## Button Behavior

- **Reset Button (GPIO 4)** - Restarts the current game
- **Exit Button** - Not used in single-game mode (can be repurposed if needed)
- **Game Controls** - Work normally for the selected game

## Troubleshooting

### Game Won't Start

1. Check that the game name is spelled correctly in the launcher script
2. Verify the game file exists in the `games/` directory
3. Check the log file: `tail -f /home/pi/arcade.log`

### Reset Button Not Working

1. Check the GPIO monitor service status:
   ```bash
   sudo systemctl status gpio-monitor-single-game
   ```
2. Check the service logs:
   ```bash
   sudo journalctl -u gpio-monitor-single-game -f
   ```

### Wrong Game Loading

1. Verify the `GAME_NAME` setting in `single-game-launcher.sh`
2. Check if the `SINGLE_GAME_NAME` environment variable is set
3. Restart the launcher after making changes

## Switching Back to Menu Mode

To switch back to the standard menu mode:

1. Restore the standard GPIO monitor:
   ```bash
   sudo systemctl stop gpio-monitor-single-game
   sudo systemctl disable gpio-monitor-single-game
   sudo systemctl enable gpio-monitor
   sudo systemctl start gpio-monitor
   ```

2. Update autostart to use the standard launcher (`launcher.sh` or `dual-chromium-launcher.sh`)

3. Switch back to the main branch:
   ```bash
   git checkout chromium-kiosk
   ```
