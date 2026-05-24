#!/usr/bin/env python3
# gpio-reset.py - Simple GPIO button monitor to trigger kill-to-menu
# Watches GPIO pin 3 (BCM) for button press and runs kill-to-menu.sh

import RPi.GPIO as GPIO
import time
import subprocess
import os

# Configuration
RESET_PIN = 3  # BCM GPIO 3 (physical pin 5)
KILL_SCRIPT = "/home/pi/CreationStationArcade-run/kill-to-menu.sh"

# Set DISPLAY for subprocess
os.environ["DISPLAY"] = ":0"

def on_button_press(channel):
    print(f"Button pressed on pin {channel}, triggering kill-to-menu...")
    try:
        subprocess.Popen(["bash", KILL_SCRIPT], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error running kill script: {e}")

def main():
    try:
        GPIO.setmode(GPIO.BCM)
        # Use pull-down since button will connect to 3.3V when pressed
        GPIO.setup(RESET_PIN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        
        # Add event detect on rising edge (button press)
        GPIO.add_event_detect(RESET_PIN, GPIO.RISING, 
                             callback=on_button_press, 
                             bouncetime=300)
        
        print(f"GPIO reset monitor started on pin {RESET_PIN}")
        print("Press button to trigger kill-to-menu")
        
        # Keep running
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    main()
