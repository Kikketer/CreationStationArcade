#!/usr/bin/env python3
# gpio-monitor.py - GPIO button monitor + inactivity timeout for Dual-Chromium kiosk
# Watches reset button, monitors GPIO activity, kills game Chromium after inactivity

import RPi.GPIO as GPIO
import time
import subprocess
import os
import threading
import signal

# Configuration
RESET_PIN = 4           # BCM GPIO 4 for reset button (from arcade.cfg BTN_RESET)
BUTTON_PINS = []        # Loaded from arcade.cfg
INACTIVITY_SECONDS = 2 * 60  # 2 minutes
GAME_PID_FILE = "/tmp/arcade-game-chromium.pid"

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

def is_game_running():
    """Check if game Chromium is running via PID file"""
    try:
        with open(GAME_PID_FILE, "r") as f:
            pid = int(f.read().strip())
        # Check if process exists
        os.kill(pid, 0)
        return True
    except (FileNotFoundError, ValueError, OSError):
        return False

def get_game_pid():
    """Get game Chromium PID from file"""
    try:
        with open(GAME_PID_FILE, "r") as f:
            return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return None

def on_button_activity(channel):
    """Any button press resets activity timer"""
    global _last_activity
    _last_activity = time.monotonic()
    log(f"Button activity on pin {channel}")

def on_reset_press(channel):
    """Reset button immediately kills game Chromium"""
    log(f"Reset button pressed on pin {channel}")
    kill_game_chromium()

def kill_game_chromium():
    """Kill game Chromium process directly via PID file"""
    pid = get_game_pid()
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
            log(f"Sent SIGTERM to game Chromium (PID: {pid})")
            # Wait a bit then force kill if still running
            time.sleep(1)
            try:
                os.kill(pid, 0)
                os.kill(pid, signal.SIGKILL)
                log(f"Force killed game Chromium (PID: {pid})")
            except OSError:
                pass  # Already dead
        except OSError as e:
            log(f"Error killing game Chromium: {e}")
    else:
        # Fallback: try to find and kill by pattern
        try:
            subprocess.run(["pkill", "-f", "chromium.*localhost:3000/play"], 
                         capture_output=True, timeout=5)
            log("Killed game Chromium via pkill pattern")
        except Exception as e:
            log(f"pkill failed: {e}")
    
    global _last_activity
    _last_activity = time.monotonic()

def inactivity_monitor():
    """Background thread: kill game Chromium if inactive"""
    global _last_activity
    log("Inactivity monitor thread started")
    while True:
        time.sleep(5)

        # Check if game is running
        game_running = is_game_running()
        log(f"Check: game_running={game_running}")

        if game_running:
            inactive_time = time.monotonic() - _last_activity
            log(f"In game, inactive for {int(inactive_time)}s (timeout: {INACTIVITY_SECONDS}s)")
            if inactive_time > INACTIVITY_SECONDS:
                log(f"TIMEOUT! Inactive for {int(inactive_time)}s in game, killing game Chromium")
                kill_game_chromium()
        else:
            # Reset timer when back at menu (so fresh start next game)
            _last_activity = time.monotonic()

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
