#!/usr/bin/env python3
# gpio-monitor.py - GPIO button monitor + inactivity timeout for Chromium kiosk
# Watches reset button and kills to menu after inactivity in game

import RPi.GPIO as GPIO
import time
import subprocess
import os
import json
import threading

# Configuration
RESET_PIN = 4           # BCM GPIO 4 for reset button (from arcade.cfg BTN_RESET)
BUTTON_PINS = []        # Loaded from arcade.cfg
INACTIVITY_SECONDS = 2 * 60  # 2 minutes
KILL_SCRIPT = "/home/pi/CreationStationArcade-run/kill-to-menu.sh"
DEBUG_PORT = 9222

# State
_last_activity = time.monotonic()
_in_game = False

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

def get_chromium_url():
    """Get current URL from Chromium debugging port"""
    try:
        import urllib.request
        with urllib.request.urlopen(f"http://localhost:{DEBUG_PORT}/json/list", timeout=2) as resp:
            data = json.loads(resp.read().decode())
            for page in data:
                if page.get("type") == "page":
                    return page.get("url", "")
    except Exception:
        pass
    return ""

def check_in_game():
    """Check if currently on a game page (not menu)"""
    url = get_chromium_url()
    return "/play?" in url

def on_button_activity(channel):
    """Any button press resets activity timer"""
    global _last_activity
    _last_activity = time.monotonic()
    log(f"Button activity on pin {channel}")

def on_reset_press(channel):
    """Reset button immediately kills to menu"""
    log(f"Reset button pressed on pin {channel}")
    trigger_kill()

def trigger_kill():
    """Run kill script"""
    try:
        subprocess.Popen(["bash", KILL_SCRIPT],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)
        global _last_activity
        _last_activity = time.monotonic()
    except Exception as e:
        log(f"Error running kill script: {e}")

def inactivity_monitor():
    """Background thread: kill to menu if inactive in game"""
    global _last_activity, _in_game
    log("Inactivity monitor thread started")
    while True:
        time.sleep(5)

        # Check if we're in a game
        _in_game = check_in_game()
        log(f"Check: in_game={_in_game}")

        if _in_game:
            inactive_time = time.monotonic() - _last_activity
            log(f"In game, inactive for {int(inactive_time)}s (timeout: {INACTIVITY_SECONDS}s)")
            if inactive_time > INACTIVITY_SECONDS:
                log(f"TIMEOUT! Inactive for {int(inactive_time)}s in game, killing to menu")
                trigger_kill()

def main():
    global _last_activity
    
    try:
        GPIO.setmode(GPIO.BCM)
        
        # Setup reset button
        GPIO.setup(RESET_PIN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        GPIO.add_event_detect(RESET_PIN, GPIO.RISING, 
                             callback=on_reset_press, 
                             bouncetime=300)
        
        # Note: Button activity monitoring disabled - no buttons wired yet
        # When buttons are wired, load from arcade.cfg and setup event detects
        _last_activity = time.monotonic()
        log("Note: Button activity monitoring disabled (no buttons wired)")
        
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
