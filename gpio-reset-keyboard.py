#!/usr/bin/env python3
# gpio-reset-keyboard.py — cabinet reset button -> uinput 'r' key
import os
import sys
import time
import struct
import fcntl
import argparse

import RPi.GPIO as GPIO

LOG_FILE = "/home/pi/arcade.log"
UINPUT_PATH = "/dev/uinput"
DEFAULT_PIN = int(os.environ.get("GPIO_RESET_PIN", "27"))

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
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] GPIO-RESET: {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def create_vkbd():
    fd = open(UINPUT_PATH, "wb+")
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pin", type=int, default=DEFAULT_PIN)
    parser.add_argument("--active-low", action="store_true")
    args = parser.parse_args()

    reset_pin = args.pin
    active_low = args.active_low
    debounce_s = 0.05

    log(f"Starting: pin={reset_pin} active_low={active_low}")
    fd = create_vkbd()

    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    pud = GPIO.PUD_UP if active_low else GPIO.PUD_DOWN
    GPIO.setup(reset_pin, GPIO.IN, pull_up_down=pud)
    active = GPIO.LOW if active_low else GPIO.HIGH

    try:
        last = None
        while True:
            state = GPIO.input(reset_pin)
            if state == active and last != active:
                time.sleep(debounce_s)
                if GPIO.input(reset_pin) == active:
                    send_r(fd)
            last = state
            time.sleep(0.01)
    finally:
        GPIO.cleanup()
        try:
            fcntl.ioctl(fd, UI_DEV_DESTROY)
            fd.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
