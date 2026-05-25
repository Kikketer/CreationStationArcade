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

### High Priority

1. **Test Dual-Chromium Mode**
   - [ ] Reboot Pi and verify menu launches
   - [ ] Select game, verify it launches on top
   - [ ] Press kill button, verify instant return to menu
   - [ ] Try launch second game while first running - should show "already running"
   - [ ] Wait 2 minutes without input - should auto-kill game

2. **GPIO Virtual Gamepad Setup** ✅
   - [x] Run `sudo ./setup-gamepad.sh` (or `bash install/kiosk-setup.sh --gpio-controllers`)
   - [x] Verify `ls /dev/input/js*` shows 4 joysticks
   - [x] Check `chrome://gamepad` in browser
   - [x] Test button mapping with actual GPIO buttons
   - [x] Integrated into kiosk setup with `--gpio-controllers` flag

3. **Button Wiring & Testing**
   - [ ] Wire reset button to GPIO 4
   - [ ] Wire player buttons per `arcade.cfg`
   - [ ] Test reset button kills game
   - [ ] Test game buttons work in games
   - [ ] Verify inactivity timeout (2 min) works

### Medium Priority

4. **gpio-monitor Systemd Service**
   - [ ] Create `gpio-monitor.service`
   - [ ] Enable auto-start on boot
   - [ ] Test reset button without manual script start

5. **Error Handling & Edge Cases**
   - [ ] Handle case where game Chromium fails to spawn
   - [ ] Handle case where menu Chromium dies unexpectedly
   - [ ] Handle window focus issues if xdotool fails
   - [ ] Log rotation for `/home/pi/arcade.log`

### Low Priority

6. **Polish & Optimization**
   - [ ] Game loading screen/spinner
   - [ ] Better error messages in menu
   - [ ] Visual feedback for "game already running"
   - [ ] Performance optimization (reduce CPU usage)

## File Locations

| File | Purpose | Status |
|------|---------|--------|
| `server.js` | Node HTTP server, spawns game Chromium | Ready |
| `menu-launcher.sh` | Launches menu Chromium + server | Ready |
| `kill-to-menu.sh` | Kills game Chromium | Ready |
| `gpio-monitor.py` | GPIO monitor + inactivity timeout | Ready |
| `gpio-gamepad.py` | Virtual USB HID gamepads | ✅ Tested & Working |
| `gpio-gamepad.service` | Systemd service for gamepad | Ready |
| `setup-gamepad.sh` | Setup script for gamepad | Ready |
| `public/index.html` | Menu UI | Ready |
| `public/play.html` | Game player UI | Ready |
| `arcade.cfg` | GPIO pin mappings | Ready |

## Known Issues

1. **gpio-monitor not auto-starting** - Currently needs manual start (need systemd service)
2. **Hardware testing incomplete** - GPIO gamepad works, needs full button wiring test
3. **GPIO reset button** - Needs wiring to GPIO 4 and testing

## Quick Commands

```bash
# Full kiosk setup (USB controllers)
bash install/kiosk-setup.sh

# Full kiosk setup with GPIO virtual gamepads
bash install/kiosk-setup.sh --gpio-controllers

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

---

Last Updated: May 24, 2026
