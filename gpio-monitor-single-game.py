#!/usr/bin/env python3
# gpio-monitor-single-game.py - GPIO button monitor for single-game kiosk
# Watches reset button and restarts the game when pressed

import RPi.GPIO as GPIO
import time
import subprocess
import os
import signal

# Configuration
RESET_PIN = 4           # BCM GPIO 4 for reset button (from arcade.cfg BTN_RESET)
# Reset button is ACTIVE LOW - connect button between GPIO 4 and Ground
DEBOUNCE_TIME = 0.3     # 300ms debounce

os.environ["DISPLAY"] = ":0"

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] {msg}")

def handle_reset():
    """Handle reset button press - restart the game"""
    log("Reset button pressed - restarting game...")
    try:
        # Run the reset script
        subprocess.run(["/home/pi/CreationStationArcade/reset-single-game.sh"], check=True)
        log("Game restart completed")
    except subprocess.CalledProcessError as e:
        log(f"Error restarting game: {e}")
    except FileNotFoundError:
        log("Reset script not found, falling back to manual restart...")
        # Fallback: kill chromium and let the launcher restart it
        subprocess.run(["pkill", "-f", "chromium.*localhost:3000"], check=False)

def signal_handler(signum, frame):
    """Clean shutdown on SIGTERM/SIGINT"""
    log("Received signal, shutting down...")
    GPIO.cleanup()
    exit(0)

def main():
    log("=== Single-Game GPIO Monitor Starting ===")
    
    # Set up signal handlers for clean shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # GPIO setup
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Configure reset pin with pull-up resistor (button connects to ground)
    GPIO.setup(RESET_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    log(f"Reset button configured on GPIO {RESET_PIN} (active low)")
    
    # Track last reset time for debouncing
    last_reset_time = 0
    
    try:
        while True:
            current_time = time.time()
            
            # Check reset button (active low)
            if not GPIO.input(RESET_PIN):  # Button pressed (LOW)
                if current_time - last_reset_time > DEBOUNCE_TIME:
                    handle_reset()
                    last_reset_time = current_time
                    
                    # Wait for button release to avoid multiple triggers
                    while not GPIO.input(RESET_PIN):
                        time.sleep(0.01)
            
            # Small sleep to prevent CPU spinning
            time.sleep(0.01)
            
    except KeyboardInterrupt:
        log("Keyboard interrupt received")
    except Exception as e:
        log(f"Error in main loop: {e}")
    finally:
        GPIO.cleanup()
        log("=== GPIO Monitor Shutdown ===")

if __name__ == "__main__":
    main()
