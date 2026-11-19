#!/usr/bin/env python3
# gpio-monitor.py - GPIO button monitor + inactivity timeout for single-window kiosk
# Watches reset button and USB gamepad activity; asks the kiosk to close the
# game iframe (route back to menu) — nothing is killed.

import RPi.GPIO as GPIO
import time
import json
import os
import threading
import struct
import select
import glob
import urllib.request

# Configuration
RESET_PIN = 4           # BCM GPIO 4 for reset button (from arcade.cfg BTN_RESET)
# Reset button is ACTIVE LOW - connect button between GPIO 4 and Ground
BUTTON_PINS = []        # Loaded from arcade.cfg
INACTIVITY_SECONDS = 2 * 60  # 2 minutes
API = "http://localhost:3000"

# State
_last_activity = time.monotonic()
_in_game = False
_joystick_fds = []      # Open joystick device file descriptors

os.environ["DISPLAY"] = ":0"

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] {msg}")

def load_button_pins():
    """Load button pins from arcade.cfg"""
    pins = []
    cfg_path = "/home/pi/CreationStationArcade/arcade.cfg"
    try:
        with open(cfg_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip()
                if key.startswith("BTN_") and key not in ("BTN_RESET", "BTN_EXIT"):
                    try:
                        pin = int(val)
                        pins.append(pin)
                    except ValueError:
                        pass
    except FileNotFoundError:
        log(f"WARNING: {cfg_path} not found")
    # De-dupe
    return list(dict.fromkeys(pins))

def api_get(path):
    """GET a JSON endpoint on the arcade server. Returns {} on failure."""
    try:
        with urllib.request.urlopen(API + path, timeout=5) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        log(f"API {path} failed: {e}")
        return {}

def is_game_running():
    """Ask the server whether the menu page has a game open."""
    return bool(api_get("/api/game-state").get("active"))

def on_button_activity(channel):
    """Any button press resets activity timer"""
    global _last_activity
    _last_activity = time.monotonic()

def on_reset_press(channel):
    """Reset button routes the kiosk back to the menu"""
    log(f"Reset button pressed on pin {channel}")
    return_to_menu()

def open_joystick_devices():
    """Open all available joystick devices for monitoring"""
    global _joystick_fds
    # Close existing
    for fd in _joystick_fds:
        try:
            os.close(fd)
        except:
            pass
    _joystick_fds = []
    
    # First, try stable arcade-p* names (if udev rules configured)
    # These are stable across reboots (arcade-p1 always = same physical port)
    for player in range(1, 5):
        stable_path = f"/dev/input/arcade-p{player}"
        if os.path.exists(stable_path):
            try:
                fd = os.open(stable_path, os.O_RDONLY | os.O_NONBLOCK)
                _joystick_fds.append(fd)
                log(f"Monitoring stable joystick: {stable_path}")
            except Exception as e:
                log(f"Could not open {stable_path}: {e}")
    
    # If no stable devices found, fall back to js* (kernel-assigned, may vary)
    if not _joystick_fds:
        log("No stable arcade-p* devices found, using js* devices (order may vary)")
        for js_path in sorted(glob.glob("/dev/input/js*")):
            try:
                fd = os.open(js_path, os.O_RDONLY | os.O_NONBLOCK)
                _joystick_fds.append(fd)
                log(f"Monitoring joystick: {js_path}")
            except Exception as e:
                log(f"Could not open {js_path}: {e}")
    
    return len(_joystick_fds)

def check_joystick_activity():
    """Check if any joystick has activity. Returns True if activity detected."""
    global _joystick_fds
    if not _joystick_fds:
        return False
    
    try:
        # Use select to check for readable data (non-blocking)
        readable, _, _ = select.select(_joystick_fds, [], [], 0)
        if readable:
            for fd in readable:
                try:
                    # Read and discard the event (just need to know there was activity)
                    data = os.read(fd, 8)
                    if data:
                        return True
                except (OSError, BlockingIOError):
                    pass
    except (OSError, ValueError):
        # Joystick disconnected? Try to reopen
        log("Joystick select failed, attempting to reopen devices")
        open_joystick_devices()
    
    return False

def return_to_menu():
    """Ask the kiosk to close the game iframe — the page swaps back itself"""
    log("Requesting return to menu via /api/kill-game")
    api_get("/api/kill-game")
    global _last_activity
    _last_activity = time.monotonic()

def inactivity_monitor():
    """Background thread: kill game Chromium if inactive"""
    global _last_activity
    log("Inactivity monitor thread started")
    
    # Open joystick devices
    js_count = open_joystick_devices()
    log(f"Monitoring {js_count} USB joystick(s) for activity")
    
    while True:
        time.sleep(1)  # Check every second for joystick activity
        
        # Check for USB gamepad activity (always, even when not in game)
        if check_joystick_activity():
            _last_activity = time.monotonic()
        
        # Check every 5 seconds for inactivity timeout
        # (use counter to avoid checking too frequently)
        if int(time.monotonic()) % 5 != 0:
            continue
        
        # Check if game is running
        game_running = is_game_running()
        
        if game_running:
            inactive_time = time.monotonic() - _last_activity
            if inactive_time > INACTIVITY_SECONDS:
                log(f"TIMEOUT! Inactive for {int(inactive_time)}s in game, returning to menu")
                return_to_menu()
            else:
                log(f"In game, inactive for {int(inactive_time)}s (timeout: {INACTIVITY_SECONDS}s)")
        else:
            # Reset timer when back at menu (so fresh start next game)
            _last_activity = time.monotonic()

def main():
    global _last_activity
    
    try:
        GPIO.setmode(GPIO.BCM)
        
        # Setup reset button - ACTIVE LOW (connect button to ground)
        # Pin is HIGH via internal pull-up, goes LOW when button pressed
        GPIO.setup(RESET_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.add_event_detect(RESET_PIN, GPIO.FALLING, 
                             callback=on_reset_press, 
                             bouncetime=300)
        log(f"Reset button configured: ACTIVE LOW (GPIO {RESET_PIN} to GND)")
        
        # Note: GPIO button activity monitoring disabled - no buttons wired yet
        # When buttons are wired, load from arcade.cfg and setup event detects
        # USB gamepad monitoring is active via joystick thread
        _last_activity = time.monotonic()
        log("Note: GPIO button monitoring disabled (no buttons wired)")
        log("Note: USB gamepad monitoring active (via /dev/input/js*)")
        
        # Start inactivity monitor thread
        monitor_thread = threading.Thread(target=inactivity_monitor, daemon=True)
        monitor_thread.start()
        
        log(f"GPIO monitor started - reset pin {RESET_PIN}, inactivity timeout {INACTIVITY_SECONDS}s")
        
        # Main loop
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        log("Exiting...")
    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    main()
