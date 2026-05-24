# Arcade GPIO Migration Notes

## Current Setup (Raspberry Pi)

The arcade controls are currently wired directly to Raspberry Pi GPIO pins using the following mapping from the `keys.cpp` module:

### Pin Mapping

| Player | Control | GPIO Pin | Key ID | Notes |
|--------|---------|----------|--------|-------|
| **Player 1** | Left | 1 | BTN_LEFT | |
| | Up | 2 | BTN_UP | |
| | Right | 3 | BTN_RIGHT | |
| | Down | 4 | BTN_DOWN | |
| | A | 5 | BTN_A | |
| | B | 6 | BTN_B | |
| | Menu | 7 | BTN_MENU | |
| **Player 2** | Left | 8 | BTN_LEFT2 | |
| | Up | 9 | BTN_UP2 | |
| | Right | 10 | BTN_RIGHT2 | |
| | Down | 11 | BTN_DOWN2 | |
| | A | 12 | BTN_A2 | |
| | B | 13 | BTN_B2 | |
| | Menu | 14 | BTN_MENU2 | |
| **Player 3** | Left | 15 | BTN_LEFT3 | |
| | Up | 16 | BTN_UP3 | |
| | Right | 17 | BTN_RIGHT3 | |
| | Down | 18 | BTN_DOWN3 | |
| | A | 19 | BTN_A3 | |
| | B | 20 | BTN_B3 | |
| | Menu | 21 | BTN_MENU3 | |
| **Player 4** | Left | 22 | BTN_LEFT4 | |
| | Up | 23 | BTN_UP4 | |
| | Right | 24 | BTN_RIGHT4 | |
| | Down | 25 | BTN_DOWN4 | |
| | A | 26 | BTN_A4 | |
| | B | 27 | BTN_B4 | |
| | Menu | 28 | BTN_MENU4 | |
| **System** | Reset | 29 | BTN_RESET | |
| | Exit | 30 | BTN_EXIT | |

### Hardware Implementation

- USB encoders were originally used but cords were cut
- Controls are now direct-wired to Pi GPIO with pull-up resistors
- `keys.cpp` reads GPIO state and raises events to TypeScript runtime
- `monitor_kill.py` listens on BCM GPIO 4 for kill signal

## Migration Options

### Option 1: Arduino USB HID Bridge (Recommended)

**Hardware:** Arduino Pro Micro (ATmega32U4) or similar with native USB

**Approach:**
- Wire arcade controls to Arduino GPIO pins (same pin numbers as Pi where possible)
- Arduino acts as USB HID keyboard device
- Maps each button to keyboard key (WASD, arrows, space, enter, etc.)
- TypeScript `controller.ts` receives key events (no code changes needed)

**Pros:**
- Minimal wiring changes (reuse existing soldered connections)
- MacBook sees standard USB keyboard
- No additional drivers needed

**Cons:**
- Requires Arduino programming
- Additional hardware component

### Option 2: USB Encoder Replacement

**Hardware:** Zero Delay USB Arcade Encoder boards (~$10 each)

**Approach:**
- Remove Pi GPIO wiring
- Re-attach to USB encoder boards
- Plug encoders into MacBook USB ports

**Pros:**
- Standard USB HID, no programming
- Plug-and-play with MacBook

**Cons:**
- Requires re-soldering all 4 player controls
- More physical work

### Option 3: USB GPIO Adapter

**Hardware:** FT232H, MCP2221, or similar USB-to-GPIO bridge

**Approach:**
- Use USB adapter to read GPIO states
- Custom macOS driver or user-space program to read GPIO and emit key events

**Pros:**
- Keeps existing wiring mostly intact

**Cons:**
- Requires custom driver/software on MacBook
- More complex than Arduino approach

## Recommended Path: Arduino Bridge

### Wiring Plan

```
Arcade Controls (existing soldered connections)
        |
        v
Arduino Pro Micro (reads GPIO, outputs USB HID)
        |
        v
MacBook USB Port (sees as keyboard)
        |
        v
ElectroBun App (receives key events)
```

### Arduino Pin Mapping

Use same pin numbers as Pi for consistency:

| Arcade Wire | Arduino Pin | Output Key |
|-------------|-------------|------------|
| P1 Left | D1 | Arrow Left |
| P1 Up | D2 | Arrow Up |
| P1 Right | D3 | Arrow Right |
| P1 Down | D4 | Arrow Down |
| P1 A | D5 | Z |
| P1 B | D6 | X |
| P1 Menu | D7 | Enter |
| P2 Left | D8 | A |
| ... | ... | ... |

### Implementation Notes

- Use Arduino Keyboard library for USB HID
- Add debouncing in Arduino code
- Consider multiple Arduinos (one per 2 players) if pin count insufficient
- Total pins needed: 28 (4 players × 7 buttons each) + 2 system = 30 pins
- Arduino Pro Micro has 18 digital I/O - may need 2 units or use analog as digital

## MacBook Boot Sequence Plan

1. **Auto-login enabled** - User logs in automatically on boot
2. **LaunchAgent plist** - macOS service starts ElectroBun app on login
3. **ElectroBun app** - Bundles web server and UI in single executable
4. **No sleep on AC** - `pmset disablesleep 1` when plugged in
5. **App handles controls** - Receives keyboard events from Arduino

## Files to Create

- [ ] `install/macos-setup.sh` - Configure MacBook for kiosk mode
- [ ] `electrobun/` - ElectroBun application source
- [ ] `arduino/arcade-bridge.ino` - Arduino sketch for GPIO-to-USB

## Testing Checklist

- [ ] MacBook boots automatically when plugged in (dead battery)
- [ ] ElectroBun app launches automatically
- [ ] Controls respond via Arduino bridge
- [ ] Games launch and exit properly
- [ ] Monitor/TV wakes on HDMI activity
