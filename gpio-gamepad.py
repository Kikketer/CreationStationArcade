#!/usr/bin/env python3
"""
gpio-gamepad.py - Create 4 virtual USB HID gamepads from GPIO inputs

Maps GPIO pins from arcade.cfg to virtual USB gamepads that browsers
see as standard USB controllers via the Gamepad API.

Player 1: BTN_UP=6, BTN_DOWN=0, BTN_LEFT=13, BTN_RIGHT=5, BTN_A=26, BTN_B=19
Player 2: BTN_UP2=22, BTN_DOWN2=17, BTN_LEFT2=10, BTN_RIGHT2=27, BTN_A2=11, BTN_B2=9
Player 3: BTN_UP3=12, BTN_DOWN3=7, BTN_LEFT3=16, BTN_RIGHT3=1, BTN_A3=21, BTN_B3=20
Player 4: BTN_UP4=23, BTN_DOWN4=15, BTN_LEFT4=24, BTN_RIGHT4=18, BTN_A4=8, BTN_B4=25

Reset button (GPIO 4) is NOT part of gamepad - handled by gpio-monitor.py
"""

import os
import sys
import time
import struct
import threading
import configparser

# Try to import uhid, if not available we'll need to install it
try:
    import uhid
except ImportError:
    print("ERROR: uhid module not installed. Run: pip3 install uhid")
    sys.exit(1)

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("ERROR: RPi.GPIO not available")
    sys.exit(1)

# Import stats tracking
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arcade_stats

LOG_FILE = "/home/pi/arcade.log"

# USB HID Gamepad Report Descriptor (16 buttons)
# MakeCode Arcade expects: 0=A, 1=B, 9=Menu, 12=Up, 13=Down, 14=Left, 15=Right
# We use buttons 12-15 for D-pad instead of hat switch for compatibility
GAMEPAD_REPORT_DESCRIPTOR = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x05,        # Usage (Game Pad)
    0xa1, 0x01,        # Collection (Application)
    0xa1, 0x00,        #   Collection (Physical)
    
    # Buttons (16 buttons: A, B, X, Y, LB, RB, back, start, L3, R3, unassigned, unassigned, Up, Down, Left, Right)
    0x05, 0x09,        #   Usage Page (Button)
    0x19, 0x01,        #   Usage Minimum (Button 1)
    0x29, 0x10,        #   Usage Maximum (Button 16)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1)
    0x95, 0x10,        #   Report Count (16)
    0x81, 0x02,        #   Input (Data, Variable, Absolute)
    
    0xc0,              #   End Collection
    0xc0,              # End Collection
])

# Gamepad button mapping (bit positions in report)
# Report format: 2 bytes, 16 buttons (little-endian bit order)
# MakeCode Arcade expects: 0=A, 1=B, 12=Up, 13=Down, 14=Left, 15=Right
BUTTON_A = 0
BUTTON_B = 1
BUTTON_X = 2   # Unused
BUTTON_Y = 3   # Unused
BUTTON_LB = 4  # Unused
BUTTON_RB = 5  # Unused
BUTTON_BACK = 6   # Unused
BUTTON_START = 7  # Unused (Menu button)
BUTTON_L3 = 8   # Unused
BUTTON_R3 = 9   # Unused
BUTTON_10 = 10  # Unused
BUTTON_11 = 11  # Unused
BUTTON_UP = 12
BUTTON_DOWN = 13
BUTTON_LEFT = 14
BUTTON_RIGHT = 15

class VirtualGamepad:
    """A single virtual USB gamepad with 16 buttons"""
    
    def __init__(self, player_num, pin_config):
        self.player_num = player_num
        self.pin_config = pin_config  # dict: { 'up': pin, 'down': pin, ... }
        
        # Current state - 16 buttons (bits 0-15)
        self.buttons = 0  # 16 bits: [RB,LB,Y,X,B,A,unused...,R,L,D,U]
        
        # Previous state for edge detection
        self.prev_buttons = 0
        
        # Create uhid device
        self.device = uhid.UHIDDevice(
            vid=0x1234,  # Vendor ID (arbitrary)
            pid=0x5678 + player_num,  # Product ID (unique per player)
            name=f"Arcade Gamepad P{player_num}",
            report_descriptor=GAMEPAD_REPORT_DESCRIPTOR,
        )
        
        # Wait for device to be ready (new uhid API)
        self.device.wait_for_start()
        log(f"Player {player_num}: Virtual gamepad created")
        
        # Initial report
        self.send_report()
    
    def send_report(self):
        """Send current state to USB HID - 2 bytes, 16 buttons little-endian"""
        # Report is 2 bytes: [buttons 0-7], [buttons 8-15]
        report = bytes([self.buttons & 0xFF, (self.buttons >> 8) & 0xFF])
        self.device.send_input(report)
    
    def update(self, pin_states):
        """Update state based on GPIO pin readings"""
        # Read GPIO states (active low)
        up = pin_states.get(self.pin_config['up'], 1) == 0
        down = pin_states.get(self.pin_config['down'], 1) == 0
        left = pin_states.get(self.pin_config['left'], 1) == 0
        right = pin_states.get(self.pin_config['right'], 1) == 0
        a_pressed = pin_states.get(self.pin_config['a'], 1) == 0
        b_pressed = pin_states.get(self.pin_config['b'], 1) == 0
        
        # Build button state (16 bits)
        new_buttons = 0
        if a_pressed:
            new_buttons |= (1 << BUTTON_A)
        if b_pressed:
            new_buttons |= (1 << BUTTON_B)
        if up:
            new_buttons |= (1 << BUTTON_UP)
        if down:
            new_buttons |= (1 << BUTTON_DOWN)
        if left:
            new_buttons |= (1 << BUTTON_LEFT)
        if right:
            new_buttons |= (1 << BUTTON_RIGHT)
        
        # Send report if changed
        if new_buttons != self.buttons:
            # Track stats for newly pressed buttons (transition from 0 to 1)
            newly_pressed = new_buttons & ~self.buttons
            if newly_pressed & (1 << BUTTON_A):
                arcade_stats.increment_button(self.player_num, 'a')
            if newly_pressed & (1 << BUTTON_B):
                arcade_stats.increment_button(self.player_num, 'b')
            if newly_pressed & (1 << BUTTON_UP):
                arcade_stats.increment_button(self.player_num, 'up')
            if newly_pressed & (1 << BUTTON_DOWN):
                arcade_stats.increment_button(self.player_num, 'down')
            if newly_pressed & (1 << BUTTON_LEFT):
                arcade_stats.increment_button(self.player_num, 'left')
            if newly_pressed & (1 << BUTTON_RIGHT):
                arcade_stats.increment_button(self.player_num, 'right')
            
            self.buttons = new_buttons
            self.send_report()


def log(msg):
    """Log with timestamp"""
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{ts}] GPIO-GAMEPAD: {msg}"
    print(line)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except:
        pass


def load_config(path):
    """Load arcade.cfg and return pin mappings for each player"""
    config = configparser.ConfigParser()
    
    # Create a section wrapper since arcade.cfg has no [section]
    with open(path, 'r') as f:
        content = f.read()
    
    # Parse manually (simple key=value format)
    pins = {}
    for line in content.split('\n'):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, val = line.split('=', 1)
            pins[key.strip()] = int(val.strip())
    
    # Map to player configs (excluding reset/menu/exit buttons)
    players = {
        1: {
            'up': pins.get('BTN_UP'),
            'down': pins.get('BTN_DOWN'),
            'left': pins.get('BTN_LEFT'),
            'right': pins.get('BTN_RIGHT'),
            'a': pins.get('BTN_A'),
            'b': pins.get('BTN_B'),
        },
        2: {
            'up': pins.get('BTN_UP2'),
            'down': pins.get('BTN_DOWN2'),
            'left': pins.get('BTN_LEFT2'),
            'right': pins.get('BTN_RIGHT2'),
            'a': pins.get('BTN_A2'),
            'b': pins.get('BTN_B2'),
        },
        3: {
            'up': pins.get('BTN_UP3'),
            'down': pins.get('BTN_DOWN3'),
            'left': pins.get('BTN_LEFT3'),
            'right': pins.get('BTN_RIGHT3'),
            'a': pins.get('BTN_A3'),
            'b': pins.get('BTN_B3'),
        },
        4: {
            'up': pins.get('BTN_UP4'),
            'down': pins.get('BTN_DOWN4'),
            'left': pins.get('BTN_LEFT4'),
            'right': pins.get('BTN_RIGHT4'),
            'a': pins.get('BTN_A4'),
            'b': pins.get('BTN_B4'),
        },
    }
    
    return players


def setup_gpio(pin_config):
    """Setup GPIO pins as inputs with pull-ups"""
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    all_pins = []
    for player, pins in pin_config.items():
        for name, pin in pins.items():
            if pin is not None:
                all_pins.append(pin)
                GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    log(f"GPIO setup complete: {len(set(all_pins))} pins configured")
    return list(set(all_pins))


def read_gpio_pins(all_pins):
    """Read all GPIO pin states"""
    return {pin: GPIO.input(pin) for pin in all_pins}


def main():
    log("Starting GPIO Virtual Gamepad Driver")
    
    # Load configuration
    cfg_path = os.path.join(os.path.dirname(__file__), 'arcade.cfg')
    if not os.path.exists(cfg_path):
        cfg_path = '/home/pi/CreationStationArcade/arcade.cfg'
    
    if not os.path.exists(cfg_path):
        log(f"ERROR: arcade.cfg not found at {cfg_path}")
        sys.exit(1)
    
    pin_config = load_config(cfg_path)
    log(f"Loaded config from {cfg_path}")
    
    # Setup GPIO
    all_pins = setup_gpio(pin_config)
    
    try:
        # Create virtual gamepads
        gamepads = {}
        for player_num in [1, 2, 3, 4]:
            if all(p is not None for p in pin_config[player_num].values()):
                gamepads[player_num] = VirtualGamepad(player_num, pin_config[player_num])
                time.sleep(0.1)  # Stagger creation
            else:
                log(f"Player {player_num}: Incomplete config, skipping")
        
        log(f"Created {len(gamepads)} virtual gamepads")
        log("Gamepads should now appear as USB devices")
        
        # Main loop - poll GPIO and update gamepads
        poll_interval = 0.016  # ~60Hz polling
        
        while True:
            pin_states = read_gpio_pins(all_pins)
            
            for player_num, gamepad in gamepads.items():
                gamepad.update(pin_states)
            
            time.sleep(poll_interval)
            
    except KeyboardInterrupt:
        log("Shutting down...")
    finally:
        GPIO.cleanup()
        for gp in gamepads.values():
            try:
                gp.device.destroy()
            except:
                pass
        log("Cleanup complete")


if __name__ == '__main__':
    main()
