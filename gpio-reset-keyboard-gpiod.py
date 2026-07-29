#!/usr/bin/env python3
# gpio-reset-keyboard-gpiod.py — cabinet reset button -> uinput 'r' key
# Board-agnostic gpiod version for non-Raspberry Pi boards (e.g. La Frite).
import os
import sys
import time
import struct
import fcntl
import argparse

import gpiod

LOG_FILE = os.environ.get("ARCADE_LOG", "/home/pi/arcade.log")
UINPUT_PATH = "/dev/uinput"
DEFAULT_CHIP = "/dev/gpiochip0"
DEFAULT_PIN = os.environ.get("GPIO_RESET_PIN", "20")

EV_KEY = 0x01
EV_SYN = 0x00
SYN_REPORT = 0
KEY_R = 19

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

UINPUT_DEV_FMT = "80sHHHHi" + "i" * 64 * 4
INPUT_EVENT_FMT = "llHHi"


def log(msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] GPIO-RESET-GPIOD: {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def create_vkbd():
    raw = os.open(UINPUT_PATH, os.O_RDWR)
    fd = os.fdopen(raw, "wb")
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_R)
    dev = struct.pack(
        UINPUT_DEV_FMT,
        b"MCArcade GPIO Reset Keyboard".ljust(80, b"\x00"),
        0x03,
        0x1234,
        0x5678,
        1,
        0,
        *([0] * 64 * 4)
    )
    fd.write(dev)
    fd.flush()
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.5)
    return fd


def emit(fd, code, value):
    t = time.time()
    sec, usec = int(t), int((t - int(t)) * 1e6)
    fd.write(struct.pack(INPUT_EVENT_FMT, sec, usec, EV_KEY, code, value))
    fd.write(struct.pack(INPUT_EVENT_FMT, sec, usec, EV_SYN, SYN_REPORT, 0))
    fd.flush()


def send_r(fd):
    emit(fd, KEY_R, 1)
    time.sleep(0.05)
    emit(fd, KEY_R, 0)
    log("Sent KEY_R (reset)")


def get_line(chip, spec):
    try:
        offset = int(spec)
        return chip.get_line(offset)
    except ValueError:
        line = chip.find_line(spec)
        if line is None:
            raise ValueError(f"GPIO line not found: {spec}")
        return line


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chip", default=DEFAULT_CHIP)
    parser.add_argument("--pin", default=DEFAULT_PIN)
    parser.add_argument("--active-low", action="store_true")
    args = parser.parse_args()

    chip_path = args.chip
    pin_spec = args.pin
    active_low = args.active_low
    debounce_s = 0.05

    log(f"Starting: chip={chip_path} pin={pin_spec} active_low={active_low}")
    fd = create_vkbd()

    try:
        chip = gpiod.Chip(chip_path)
        line = get_line(chip, pin_spec)

        flags = 0
        if active_low:
            active = 0
            try:
                flags |= gpiod.LINE_REQ_FLAG_BIAS_PULL_UP
            except AttributeError:
                log("WARNING: gpiod pull-up bias not available; use an external pull-up")
        else:
            active = 1
            try:
                flags |= gpiod.LINE_REQ_FLAG_BIAS_PULL_DOWN
            except AttributeError:
                log("WARNING: gpiod pull-down bias not available; use an external pull-down")

        line.request(
            consumer="MCArcade GPIO Reset Keyboard",
            type=gpiod.LINE_REQ_DIR_IN,
            flags=flags,
        )

        try:
            last = None
            while True:
                state = line.get_value()
                if last is None:
                    log(f"Initial GPIO state on {pin_spec}: {state}")
                elif state != last:
                    log(f"GPIO state changed on {pin_spec}: {last} -> {state}")
                if state == active and last != active:
                    time.sleep(debounce_s)
                    if line.get_value() == active:
                        send_r(fd)
                last = state
                time.sleep(0.01)
        finally:
            line.release()
            chip.close()
    finally:
        try:
            fcntl.ioctl(fd, UI_DEV_DESTROY)
            fd.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
