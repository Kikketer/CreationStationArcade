# Creation Station Arcade - TODO & Status

## Current Architecture (Single-Window Mode)

```
┌─────────────────────────────────────────────────────────────────┐
│                     NODE SERVER (server.js)                      │
│  • Serves static files (public/)                                │
│  • /api/games - list available games                              │
│  • /api/launch-game?name=XXX - marks game active (stats/409)    │
│  • /api/game-state / game-closed / kill-game - game lifecycle   │
│  • /api/heartbeat - activity ping                               │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│              KIOSK CHROMIUM (the only window ever opened)        │
│              http://localhost:3000/                             │
│              Menu page swaps the game in via #game-frame         │
│              (play.html in an iframe) — instant, nothing killed  │
│              Reset button → /api/kill-game → page routes back    │
└─────────────────────────────────────────────────────────────────┘
```

## Completed Work

### Menu Refactor - DOM + NES.css ✅
- [x] Refactored from Canvas to pure DOM with NES.css styling
- [x] 160x120 virtual resolution with pixel-perfect scaling
- [x] Two-column grid layout with tight spacing
- [x] Pulsing border animation on selected game (1px grow/shrink)
- [x] Animated GIF support - swaps PNG→GIF on selection
- [x] Player count floating over game images
- [x] Instant snap scrolling (no smooth animation)
- [x] Cached placeholder images to prevent flicker
- [x] Keyboard: Arrow keys, Enter, Space, Z
- [x] Gamepad: D-pad + A button (button 0)
- [x] Pixel art loading animation on play.html

### Git Sync & Branch Management
- [x] Fixed git sync to use `chromium-kiosk` branch (not `main`)
- [x] Made git sync non-blocking in `kill-to-menu.sh`
- [x] Background sync runs on slow/no WiFi without blocking menu

### Single-Window Architecture (iframe swap)
- [x] `server.js` - Tracks game state only (`/api/game-state`, `/api/game-closed`); no process spawning
- [x] `menu-launcher.sh` - Launches the one kiosk Chromium + Node server
- [x] `menu.js` - `#game-frame` iframe swap; `/api/game-state` poll; `arcade-exit` postMessage
- [x] `play.html` - Runs inside the menu's iframe; exits postMessage to the shell
- [x] Singleton protection - API returns 409 if game already running
- [x] No window management at all — menu page never dies, swap is ~instant

### GPIO Monitor (Single-Window Ready)
- [x] `gpio-monitor.py` - Asks the server to close the game (no process kill)
- [x] Reset button → `/api/kill-game` → page routes back to menu
- [x] Inactivity monitor returns to menu after 2 minutes
- [x] Timer resets when back at menu

### GPIO Hardware Setup ✅ (Fully Tested)
- [x] Reset button wired to GPIO 4 (BCM) - active low (ground to pin)
- [x] All player buttons wired per `arcade.cfg` (active low)
- [x] `gpio-gamepad.py` - Virtual USB gamepads from GPIO inputs
- [x] `gpio-gamepad.service` - Auto-start on boot
- [x] `gpio-monitor.service` - Reset button + inactivity monitoring
- [x] **TESTED** - 4-player GPIO virtual gamepads working in games
- [x] **TESTED** - Reset button kills game instantly
- [x] **TESTED** - 2-minute inactivity timeout working

### Virtual USB Gamepad ✅ (Tested & Working)
- [x] `gpio-gamepad.py` - Creates 4 virtual USB HID gamepads from GPIO (16-button descriptor)
- [x] `gpio-gamepad.service` - Systemd auto-start service
- [x] `setup-gamepad.sh` - One-command setup script
- [x] **TESTED** - Works with MakeCode Arcade (buttons 0-1 for A/B, 12-15 for D-pad)

## Pending / Next Steps

### Hardware Wiring (Big Haul) 🛠️ ✅ COMPLETE

1. **Button Wiring & Testing** ✅
   - [x] Wire reset button to GPIO 4
   - [x] Wire player buttons per `arcade.cfg`
   - [x] Test reset button kills game
   - [x] Test game buttons work in games
   - [x] Verify inactivity timeout (2 min) works

2. **gpio-monitor Systemd Service** ✅
   - [x] Create `gpio-monitor.service`
   - [x] Enable auto-start on boot
   - [x] Test reset button without manual script start

### Menu Polish 🎨

3. **Images & Assets**
   - [ ] Create/assign game images (PNG + animated GIF)
   - [ ] Design top logo/header artwork
   - [ ] Test placeholder fallbacks work

4. **Testing & Edge Cases**
   - [ ] Test all 4 games launch correctly
   - [ ] Test arrow navigation with full game list
   - [ ] Verify no flickering on scroll
   - [ ] Test gamepad navigation end-to-end

## File Locations

| File | Purpose | Status |
|------|---------|--------|
| `server.js` | Node HTTP server, tracks game state | Ready |
| `menu-launcher.sh` | Launches the kiosk Chromium + server | Ready |
| `kill-to-menu.sh` | Routes back to menu via `/api/kill-game` | Ready |
| `install/kiosk-setup.sh` | Pi 5 one-shot kiosk setup (with `--gpio-controllers` option) | ✅ Single-window |
| `install/debian-x86-setup.sh` | Debian x86 one-shot kiosk setup (USB controllers, Plymouth splash) | ✅ Single-window |
| `setup-usb-controllers.sh` | Configure stable USB controller ordering by physical port | ✅ Stable P1-P4 |
| `install/usb-controllers.udev` | Udev rules template for USB controller stability | ✅ Template |
| `gpio-monitor.py` | GPIO monitor + inactivity timeout | Ready |
| `gpio-gamepad.py` | Virtual USB HID gamepads | ✅ Tested & Working |
| `gpio-gamepad.service` | Systemd service for gamepad | Ready |
| `setup-gamepad.sh` | Setup script for gamepad | Ready |
| `public/index.html` | Menu UI (NES.css DOM-based) | ✅ Ready |
| `public/menu.js` | Menu logic (navigation, launch) | ✅ Ready |
| `public/style.css` | Menu styles (160x120 virtual res) | ✅ Ready |
| `public/play.html` | Game player UI (pixel loading) | ✅ Ready |
| `games/games.json` | Game metadata (name, players, file) | ✅ Ready |
| `arcade.cfg` | GPIO pin mappings | Ready |

## Known Issues

None - system is ready for hardware integration.

## Quick Commands

```bash
# Raspberry Pi 5 kiosk setup (USB controllers)
bash install/kiosk-setup.sh

# Raspberry Pi 5 kiosk setup with GPIO virtual gamepads
bash install/kiosk-setup.sh --gpio-controllers

# Debian/Ubuntu x86 kiosk setup (USB controllers, single-window)
bash install/debian-x86-setup.sh

# Configure stable USB controller ordering (run after plugging in controllers)
sudo bash setup-usb-controllers.sh

# Start GPIO monitor manually
sudo python3 /home/pi/CreationStationArcade-run/gpio-monitor.py

# Setup virtual gamepads manually
sudo /home/pi/CreationStationArcade/setup-gamepad.sh

# Kill game and return to menu
bash /home/pi/CreationStationArcade-run/kill-to-menu.sh

# Check what's running
ps aux | grep -E "chromium|node|gpio-monitor"

# View logs
tail -f /home/pi/arcade.log

# Check gamepad devices
ls /dev/input/js*
```

## Branch: `chromium-kiosk`

All work committed to `chromium-kiosk` branch. To resume:

```bash
cd /home/pi/CreationStationArcade
git fetch origin
git reset --hard origin/chromium-kiosk
rsync -a --delete --exclude ".git" --exclude "arcade.log" ./ ../CreationStationArcade-run/
```

## Fresh Install

**Raspberry Pi 5 (with GPIO gamepads):**
```bash
cd /home/pi/CreationStationArcade
bash install/kiosk-setup.sh --gpio-controllers
sudo reboot
```

**Raspberry Pi 5 (USB controllers only):**
```bash
cd /home/pi/CreationStationArcade
bash install/kiosk-setup.sh
sudo reboot
```

**Debian/Ubuntu x86 (USB controllers):**
```bash
cd ~/CreationStationArcade
bash install/debian-x86-setup.sh
sudo reboot
```

---

## USB Controller Stability (Multi-Player Setup)

**Problem:** USB controllers get random `js0`, `js1`, `js2` assignments on each boot.
**Solution:** Udev rules create stable device names based on **USB physical port**.

**After setup:**
- `arcade-p1` → Player 1 controller (always same USB port)
- `arcade-p2` → Player 2 controller (always same USB port)
- `arcade-p3` → Player 3 controller
- `arcade-p4` → Player 4 controller

**Setup Steps:**
1. Plug each controller into its intended USB port
2. Run: `sudo bash setup-usb-controllers.sh`
3. Follow prompts to identify ports and install rules
4. Reboot

**Verify after reboot:**
```bash
ls -la /dev/input/arcade-p*
# Should show stable symlinks like: arcade-p1 -> js4
```

**This works on both:**
- Raspberry Pi 5 (with USB controllers instead of GPIO)
- Debian/Ubuntu x86 systems

---

Last Updated: May 25, 2026 (GPIO Hardware Fully Tested & Working)
