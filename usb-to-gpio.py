#!/usr/bin/env python3
# usb-to-gpio.py — Reads USB gamepad input events and drives GPIO pins
# as outputs (active LOW) so the MakeCode Arcade ELF can read them.
#
# The ELF reads GPIO pins as active-low inputs (button press = pin LOW).
# This script sets those same pins as outputs and pulls them LOW/HIGH
# to simulate button presses from a USB gamepad.
#
# Usage: python3 usb-to-gpio.py
# Run in background before launching the ELF (launcher.sh does this).

import os
import sys
import time
import struct
import threading
import glob

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("ERROR: RPi.GPIO not installed. Run: sudo apt-get install python3-rpi.gpio")
    sys.exit(1)

LOG_FILE = "/home/pi/arcade.log"

# JS event format: time(4), value(2), type(1), number(1)
JS_EVENT_FMT = "IhBB"
JS_EVENT_SIZE = struct.calcsize(JS_EVENT_FMT)
JS_EVENT_BUTTON = 0x01
JS_EVENT_AXIS   = 0x02
JS_EVENT_INIT   = 0x80

# Standard USB gamepad button/axis mapping
# These are typical for most USB gamepads (Xbox-style layout)
AXIS_X      = 0   # Left stick X  (or D-pad X on some pads)
AXIS_Y      = 1   # Left stick Y  (or D-pad Y on some pads)
AXIS_DPAD_X = 6   # D-pad X (hat)
AXIS_DPAD_Y = 7   # D-pad Y (hat)
BTN_A       = 0
BTN_B       = 1
BTN_X       = 2
BTN_Y       = 3

AXIS_THRESHOLD = 16384  # Half of 32767

# arcade.cfg pin layout — matches the repo's arcade.cfg
# Each player: up, down, left, right, a, b
PLAYER_PINS = {
    1: {'up': 6,  'down': 0,  'left': 13, 'right': 5,  'a': 26, 'b': 19},
    2: {'up': 22, 'down': 17, 'left': 10, 'right': 27, 'a': 11, 'b': 9},
    3: {'up': 12, 'down': 7,  'left': 16, 'right': 1,  'a': 21, 'b': 20},
    4: {'up': 23, 'down': 15, 'left': 24, 'right': 18, 'a': 8,  'b': 25},
}


def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{ts}] USB-TO-GPIO: {msg}"
    print(line)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except Exception:
        pass


def load_pins_from_cfg():
    """Override PLAYER_PINS from arcade.cfg if present."""
    cfg_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'arcade.cfg')
    if not os.path.exists(cfg_path):
        log("arcade.cfg not found, using built-in pin defaults")
        return

    mapping = {
        1: {}, 2: {}, 3: {}, 4: {},
    }
    key_map = {
        'BTN_UP': (1, 'up'),    'BTN_DOWN': (1, 'down'),
        'BTN_LEFT': (1, 'left'),'BTN_RIGHT': (1, 'right'),
        'BTN_A': (1, 'a'),      'BTN_B': (1, 'b'),
        'BTN_UP2': (2, 'up'),   'BTN_DOWN2': (2, 'down'),
        'BTN_LEFT2': (2, 'left'),'BTN_RIGHT2': (2, 'right'),
        'BTN_A2': (2, 'a'),     'BTN_B2': (2, 'b'),
        'BTN_UP3': (3, 'up'),   'BTN_DOWN3': (3, 'down'),
        'BTN_LEFT3': (3, 'left'),'BTN_RIGHT3': (3, 'right'),
        'BTN_A3': (3, 'a'),     'BTN_B3': (3, 'b'),
        'BTN_UP4': (4, 'up'),   'BTN_DOWN4': (4, 'down'),
        'BTN_LEFT4': (4, 'left'),'BTN_RIGHT4': (4, 'right'),
        'BTN_A4': (4, 'a'),     'BTN_B4': (4, 'b'),
    }

    with open(cfg_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, val = line.split('=', 1)
            key, val = key.strip(), val.strip()
            if key in key_map:
                player, button = key_map[key]
                try:
                    mapping[player][button] = int(val)
                except ValueError:
                    pass

    for player, buttons in mapping.items():
        if buttons:
            PLAYER_PINS[player].update(buttons)

    log(f"Loaded pin config from {cfg_path}")


def setup_gpio():
    """Set all game pins as outputs, start HIGH (not pressed)."""
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    all_pins = set()
    for player_pins in PLAYER_PINS.values():
        for pin in player_pins.values():
            if pin is not None:
                all_pins.add(pin)

    for pin in all_pins:
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.HIGH)

    log(f"GPIO setup: {len(all_pins)} pins as outputs (HIGH=released)")
    return all_pins


def set_pin(pin, pressed):
    """Drive pin LOW for pressed, HIGH for released."""
    if pin is None:
        return
    try:
        GPIO.output(pin, GPIO.LOW if pressed else GPIO.HIGH)
    except Exception as e:
        log(f"GPIO error on pin {pin}: {e}")


class GamepadReader(threading.Thread):
    """Reads one /dev/input/jsN and drives GPIO pins."""

    def __init__(self, js_path, player_num):
        super().__init__(daemon=True)
        self.js_path = js_path
        self.player_num = player_num
        self.pins = PLAYER_PINS.get(player_num, {})
        self.running = True
        # Track axis state for D-pad
        self.axis_state = {}

    def _handle_button(self, number, value):
        pressed = bool(value)
        if number == BTN_A:
            set_pin(self.pins.get('a'), pressed)
        elif number == BTN_B or number == BTN_X or number == BTN_Y:
            set_pin(self.pins.get('b'), pressed)

    def _handle_axis(self, number, value):
        self.axis_state[number] = value

        # D-pad hat axes (most common on USB pads)
        if number == AXIS_DPAD_X or number == AXIS_X:
            set_pin(self.pins.get('left'),  value < -AXIS_THRESHOLD)
            set_pin(self.pins.get('right'), value >  AXIS_THRESHOLD)
        elif number == AXIS_DPAD_Y or number == AXIS_Y:
            set_pin(self.pins.get('up'),   value < -AXIS_THRESHOLD)
            set_pin(self.pins.get('down'), value >  AXIS_THRESHOLD)

    def release_all(self):
        for pin in self.pins.values():
            set_pin(pin, False)

    def run(self):
        log(f"Player {self.player_num}: watching {self.js_path}")
        while self.running:
            try:
                with open(self.js_path, 'rb') as f:
                    while self.running:
                        data = f.read(JS_EVENT_SIZE)
                        if len(data) < JS_EVENT_SIZE:
                            break
                        _, value, ev_type, number = struct.unpack(JS_EVENT_FMT, data)
                        ev_type &= ~JS_EVENT_INIT  # strip init flag
                        if ev_type == JS_EVENT_BUTTON:
                            self._handle_button(number, value)
                        elif ev_type == JS_EVENT_AXIS:
                            self._handle_axis(number, value)
            except (FileNotFoundError, OSError):
                pass
            finally:
                self.release_all()

            if self.running:
                time.sleep(2)  # Wait before retrying if device disconnected


def find_joysticks():
    return sorted(glob.glob('/dev/input/js*'))


def main():
    log("=== usb-to-gpio starting ===")
    load_pins_from_cfg()
    setup_gpio()

    readers = {}

    try:
        while True:
            current_js = find_joysticks()

            # Start readers for newly connected joysticks
            for i, js_path in enumerate(current_js):
                player_num = i + 1
                if player_num > 4:
                    break
                if js_path not in readers or not readers[js_path].is_alive():
                    reader = GamepadReader(js_path, player_num)
                    reader.start()
                    readers[js_path] = reader
                    log(f"Player {player_num}: connected {js_path}")

            # Clean up dead readers for disconnected devices
            for js_path in list(readers.keys()):
                if js_path not in current_js:
                    readers[js_path].running = False
                    readers[js_path].release_all()
                    del readers[js_path]
                    log(f"Removed {js_path}")

            time.sleep(1)

    except KeyboardInterrupt:
        log("Shutting down...")
    finally:
        for r in readers.values():
            r.running = False
            r.release_all()
        GPIO.cleanup()
        log("Cleanup complete")


if __name__ == '__main__':
    main()
