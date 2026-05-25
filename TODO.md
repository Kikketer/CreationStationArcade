# Creation Station Arcade - TODO & Status

## Current Architecture (Dual-Chromium Mode)

```
┌─────────────────────────────────────────────────────────────────┐
│                     NODE SERVER (server.js)                      │
│  • Serves static files (public/)                                │
│  • /api/games - list available games                              │
│  • /api/launch-game?name=XXX - spawns game Chromium             │
│  • /api/heartbeat - activity ping                               │
│  • Manages game process via child_process.spawn()              │
│  • Handles window focus (xdotool)                               │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│              GAME CHROMIUM (spawned by server)                  │
│              http://localhost:3000/play?game=XXX               │
│              Kill button → dies instantly, menu revealed!        │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│              MENU CHROMIUM (always running via xinitrc)          │
│              http://localhost:3000/                             │
│              Never killed, always ready for instant return       │
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

### Dual-Chromium Architecture
- [x] `server.js` - Spawns game Chromium directly via `child_process.spawn()`
- [x] `menu-launcher.sh` - Launches menu Chromium + Node server
- [x] Singleton protection - API returns 409 if game already running
- [x] Window focus management - lowers menu, raises game, refocuses menu on exit
- [x] PID file tracking - `/tmp/arcade-game-chromium.pid`
- [x] DISPLAY env fix for Chromium spawning

### GPIO Monitor (Dual-Chromium Ready)
- [x] `gpio-monitor.py` - Updated for PID-based game detection
- [x] Kill game Chromium directly via PID file (not Chrome DevTools)
- [x] Reset button kills game Chromium only
- [x] Inactivity monitor kills game after 2 minutes
- [x] Timer resets when back at menu

### Virtual USB Gamepad ✅ (Tested & Working)
- [x] `gpio-gamepad.py` - Creates 4 virtual USB HID gamepads from GPIO (16-button descriptor)
- [x] `gpio-gamepad.service` - Systemd auto-start service
- [x] `setup-gamepad.sh` - One-command setup script
- [x] **TESTED** - Works with MakeCode Arcade (buttons 0-1 for A/B, 12-15 for D-pad)

## Pending / Next Steps

### Hardware Wiring (Big Haul) 🛠️

1. **Button Wiring & Testing**
   - [ ] Wire reset button to GPIO 4
   - [ ] Wire player buttons per `arcade.cfg`
   - [ ] Test reset button kills game
   - [ ] Test game buttons work in games
   - [ ] Verify inactivity timeout (2 min) works

2. **gpio-monitor Systemd Service**
   - [ ] Create `gpio-monitor.service`
   - [ ] Enable auto-start on boot
   - [ ] Test reset button without manual script start

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
| `server.js` | Node HTTP server, spawns game Chromium | Ready |
| `menu-launcher.sh` | Launches menu Chromium + server | Ready |
| `kill-to-menu.sh` | Kills game Chromium | Ready |
| `install/kiosk-setup.sh` | Pi 5 one-shot kiosk setup (with `--gpio-controllers` option) | ✅ Dual-chromium |
| `install/debian-x86-setup.sh` | Debian x86 one-shot kiosk setup (USB controllers) | ✅ Dual-chromium |
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

# Debian/Ubuntu x86 kiosk setup (USB controllers, dual-chromium)
bash install/debian-x86-setup.sh

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

Last Updated: May 25, 2026 (Menu Refactor Complete)
