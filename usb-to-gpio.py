#!/usr/bin/env python3
# usb-to-gpio.py — Maps USB gamepad events to a uinput virtual keyboard
# so the MakeCode Arcade ELF can read inputs via /dev/input/eventX.
#
# The ELF reads keyboard scan codes from the device listed in SCAN_CODES=
# in /sd/arcade.cfg. This script creates a virtual keyboard and injects
# the correct scan codes when USB gamepad buttons/axes are pressed.
#
# Usage: python3 usb-to-gpio.py
# Run in background before launching the ELF (launcher.sh does this).

import os
import sys
import time
import struct
import threading
import glob
import fcntl

LOG_FILE = "/home/pi/arcade.log"
SD_ARCADE_CFG = "/sd/arcade.cfg"

# JS event: time(4), value(2), type(1), number(1)
JS_EVENT_FMT = "IhBB"
JS_EVENT_SIZE = struct.calcsize(JS_EVENT_FMT)
JS_EVENT_BUTTON = 0x01
JS_EVENT_AXIS   = 0x02
JS_EVENT_INIT   = 0x80

AXIS_THRESHOLD = 16384

# USB gamepad button indices (standard layout)
JS_BTN_A = 0
JS_BTN_B = 1
JS_BTN_X = 2
JS_BTN_Y = 3
JS_BTN_LB = 4
JS_BTN_RB = 5
JS_BTN_SELECT = 6
JS_BTN_START  = 7
JS_BTN_RESET  = 8   # BTN_THUMB2 — hard kill reset

# Axes
JS_AXIS_LX    = 0
JS_AXIS_LY    = 1
JS_AXIS_DPADX = 6
JS_AXIS_DPADY = 7

# Linux scan codes matching sd-arcade.cfg
# Player 1
SC_LEFT  = 105
SC_RIGHT = 106
SC_UP    = 103
SC_DOWN  = 108
SC_A     = 44   # Z
SC_B     = 45   # X
SC_EXIT  = 1    # Esc
SC_MENU  = 60   # F2

# uinput constants
UINPUT_PATH = "/dev/uinput"
UI_SET_EVBIT  = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY= 0x5502
EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0

# All scan codes we'll emit
ALL_KEYS = [SC_LEFT, SC_RIGHT, SC_UP, SC_DOWN, SC_A, SC_B, SC_EXIT, SC_MENU]

# uinput_user_dev struct
UINPUT_DEV_FMT = "80sHHHHi" + "i" * 64 * 4
UINPUT_DEV_SIZE = struct.calcsize(UINPUT_DEV_FMT)

# input_event struct: timeval(8+8), type(2), code(2), value(4)
INPUT_EVENT_FMT = "llHHi"
INPUT_EVENT_SIZE = struct.calcsize(INPUT_EVENT_FMT)


def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{ts}] USB-TO-GPIO: {msg}"
    print(line)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except Exception:
        pass


def create_virtual_keyboard():
    """Create a uinput virtual keyboard device, return fd."""
    try:
        fd = open(UINPUT_PATH, 'wb')
    except OSError as e:
        log(f"ERROR: Cannot open {UINPUT_PATH}: {e}")
        log("Try: sudo modprobe uinput")
        sys.exit(1)

    # Enable EV_KEY events
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for key in ALL_KEYS:
        fcntl.ioctl(fd, UI_SET_KEYBIT, key)

    # Build uinput_user_dev struct
    name = b"MCArcade Virtual Keyboard"
    dev = struct.pack(UINPUT_DEV_FMT,
        name.ljust(80, b'\x00'),
        0x03,   # BUS_USB
        0x1234, # vendor
        0x5678, # product
        1,      # version
        0,      # ff_effects_max
        *([0] * 64 * 4)  # absmax/absmin/absfuzz/absflat
    )
    fd.write(dev)
    fd.flush()
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.5)  # let the device appear
    log("Virtual keyboard created")
    return fd


def emit_key(fd, scancode, pressed):
    """Emit a key press/release event."""
    value = 1 if pressed else 0
    t = time.time()
    ts_sec = int(t)
    ts_usec = int((t - ts_sec) * 1e6)
    ev = struct.pack(INPUT_EVENT_FMT, ts_sec, ts_usec, EV_KEY, scancode, value)
    syn = struct.pack(INPUT_EVENT_FMT, ts_sec, ts_usec, EV_SYN, SYN_REPORT, 0)
    fd.write(ev)
    fd.write(syn)
    fd.flush()


def update_sd_arcade_cfg():
    """Find the virtual keyboard's eventX and update SCAN_CODES in /sd/arcade.cfg."""
    # Give udev a moment to create the device
    time.sleep(1)
    # Find the most recently created event device — our virtual keyboard
    events = sorted(glob.glob('/dev/input/event*'), key=os.path.getmtime, reverse=True)
    if not events:
        log("WARNING: No /dev/input/event* found, SCAN_CODES not updated")
        return
    event_dev = events[0]
    log(f"Virtual keyboard at {event_dev}, updating {SD_ARCADE_CFG}")
    try:
        with open(SD_ARCADE_CFG, 'r') as f:
            lines = f.readlines()
        with open(SD_ARCADE_CFG, 'w') as f:
            for line in lines:
                if line.startswith('SCAN_CODES='):
                    f.write(f'SCAN_CODES={event_dev}\n')
                else:
                    f.write(line)
        log(f"SCAN_CODES set to {event_dev}")
    except Exception as e:
        log(f"ERROR updating {SD_ARCADE_CFG}: {e}")


class GamepadReader(threading.Thread):
    def __init__(self, js_path, vkbd_fd):
        super().__init__(daemon=True)
        self.js_path = js_path
        self.fd = vkbd_fd
        self.running = True
        self.axis_state = {}
        self.key_state = {}

    def _set_key(self, scancode, pressed):
        if self.key_state.get(scancode) == pressed:
            return
        self.key_state[scancode] = pressed
        emit_key(self.fd, scancode, pressed)

    def _handle_button(self, number, value):
        pressed = bool(value)
        if number == JS_BTN_A:
            self._set_key(SC_A, pressed)
        elif number in (JS_BTN_B, JS_BTN_X, JS_BTN_Y):
            self._set_key(SC_B, pressed)
        elif number in (JS_BTN_SELECT,):
            self._set_key(SC_EXIT, pressed)
        elif number in (JS_BTN_START,):
            self._set_key(SC_MENU, pressed)
        elif number == JS_BTN_RESET and pressed:
            log("USB-TO-GPIO: Reset button pressed — killing elf")
            os.system("pkill -9 -f '\\.elf'")

    def _handle_axis(self, number, value):
        self.axis_state[number] = value
        # Horizontal axes: 0 (LX), 2 (ABS_Z/RX on some pads), 4, 6 (hat)
        if number in (0, 2, 4, 6):
            self._set_key(SC_LEFT,  value < -AXIS_THRESHOLD)
            self._set_key(SC_RIGHT, value >  AXIS_THRESHOLD)
        # Vertical axes: 1 (LY), 3 (ABS_RZ/RY on some pads), 5, 7 (hat)
        elif number in (1, 3, 5, 7):
            self._set_key(SC_UP,   value < -AXIS_THRESHOLD)
            self._set_key(SC_DOWN, value >  AXIS_THRESHOLD)

    def release_all(self):
        for sc in list(self.key_state.keys()):
            if self.key_state.get(sc):
                emit_key(self.fd, sc, False)
                self.key_state[sc] = False

    def run(self):
        log(f"Watching {self.js_path}")
        while self.running:
            try:
                with open(self.js_path, 'rb') as f:
                    while self.running:
                        data = f.read(JS_EVENT_SIZE)
                        if len(data) < JS_EVENT_SIZE:
                            break
                        _, value, ev_type, number = struct.unpack(JS_EVENT_FMT, data)
                        ev_type &= ~JS_EVENT_INIT
                        if ev_type == JS_EVENT_BUTTON:
                            self._handle_button(number, value)
                        elif ev_type == JS_EVENT_AXIS:
                            self._handle_axis(number, value)
            except (FileNotFoundError, OSError):
                pass
            finally:
                self.release_all()
            if self.running:
                time.sleep(2)


def main():
    setup_only = "--setup-only" in sys.argv
    log(f"=== usb-to-gpio (uinput keyboard mode) starting{'  [setup-only]' if setup_only else ''} ===")

    # Load uinput kernel module if needed
    os.system("modprobe uinput 2>/dev/null")

    vkbd_fd = create_virtual_keyboard()
    update_sd_arcade_cfg()

    if setup_only:
        log("Setup complete, keeping virtual keyboard open in background...")
        # Don't exit — if we close vkbd_fd the device disappears
        # Fork a child to hold the fd open, parent exits cleanly for the launcher
        child = os.fork()
        if child > 0:
            # Parent exits so launcher.sh can continue
            sys.exit(0)
        # Child: hold fd open and do nothing (device stays alive)
        import signal
        signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
        while True:
            time.sleep(60)
        return

    readers = {}
    try:
        while True:
            current_js = sorted(glob.glob('/dev/input/js*'))
            for js_path in current_js:
                if js_path not in readers or not readers[js_path].is_alive():
                    r = GamepadReader(js_path, vkbd_fd)
                    r.start()
                    readers[js_path] = r
                    log(f"Connected: {js_path}")
            for js_path in list(readers.keys()):
                if js_path not in current_js:
                    readers[js_path].running = False
                    del readers[js_path]
                    log(f"Disconnected: {js_path}")
            time.sleep(1)
    except KeyboardInterrupt:
        log("Shutting down...")
    finally:
        for r in readers.values():
            r.running = False
            r.release_all()
        try:
            fcntl.ioctl(vkbd_fd, UI_DEV_DESTROY)
            vkbd_fd.close()
        except Exception:
            pass
        log("Cleanup complete")


if __name__ == '__main__':
    main()
