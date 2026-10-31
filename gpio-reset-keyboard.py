#!/usr/bin/env python3
# gpio-reset-keyboard.py — cabinet reset button -> uinput 'r' key
import os
import sys
import time
import struct
import fcntl
import argparse
import signal

import RPi.GPIO as GPIO

LOG_FILE = "/home/pi/arcade.log"
UINPUT_PATH = "/dev/uinput"
# GPIO 14 (physical pin 8) is the only 40-pin header GPIO not used by the
# default /etc/arcade.cfg button map, so it never conflicts with player buttons.
# Requires the UART serial console to be disabled (the Pi OS default).
DEFAULT_PIN = int(os.environ.get("GPIO_RESET_PIN", "14"))

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
    # "wb+" needs a seekable file; /dev/uinput is a character device.
    # os.open + unbuffered fdopen avoids the seek probe entirely.
    fd = os.fdopen(os.open(UINPUT_PATH, os.O_RDWR), "wb", buffering=0)
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


def archive_request():
    # If the menu armed an archive (delete-combo held), move the named
    # game out of games/ into games/.archived/ before the kill. The
    # relaunched menu then shows the list without it.
    req = os.environ.get("ARCADE_ARCHIVE_FILE", "/tmp/creationstation_archive_request")
    games = os.environ.get("ARCADE_GAMES_DIR", "")
    if not games:
        return
    try:
        with open(req) as f:
            name = f.read().strip()
    except FileNotFoundError:
        return
    except Exception as e:
        log(f"Archive request unreadable: {e}")
        return
    try:
        os.unlink(req)
    except Exception:
        pass
    if not name or name.startswith(".") or "/" in name:
        log(f"Ignoring bogus archive request '{name}'")
        return
    src = os.path.join(games, name)
    if not os.path.isdir(src):
        log(f"Archive request for '{name}' but {src} is missing")
        return
    dst_dir = os.path.join(games, ".archived")
    dst = os.path.join(dst_dir, name)
    try:
        os.makedirs(dst_dir, exist_ok=True)
        if os.path.exists(dst):
            dst = os.path.join(dst_dir, f"{name}.{int(time.time())}")
        os.rename(src, dst)
        log(f"Archived '{name}' -> {dst}")
    except Exception as e:
        log(f"Archive move failed for '{name}': {e}")


def kill_pidfile(path):
    try:
        with open(path) as f:
            pid = int(f.read().strip())
        os.kill(pid, signal.SIGKILL)
        log(f"Sent SIGKILL to pid {pid} from {path}")
    except FileNotFoundError:
        log(f"No pidfile at {path}; nothing to kill")
    except Exception as e:
        log(f"Kill failed for {path}: {e}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pin", type=int, default=DEFAULT_PIN)
    parser.add_argument("--active-low", action="store_true")
    parser.add_argument("--pidfile", default=os.environ.get("GPIO_RESET_PIDFILE", ""),
                        help="kill the pid in this file instead of injecting an 'r' key")
    args = parser.parse_args()

    reset_pin = args.pin
    active_low = args.active_low
    debounce_s = 0.05

    log(f"Starting: pin={reset_pin} active_low={active_low} pidfile={args.pidfile or '<none>'}")
    fd = None if args.pidfile else create_vkbd()

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
                    if args.pidfile:
                        archive_request()
                        kill_pidfile(args.pidfile)
                    else:
                        send_r(fd)
            last = state
            time.sleep(0.01)
    finally:
        GPIO.cleanup()
        if fd is not None:
            try:
                fcntl.ioctl(fd, UI_DEV_DESTROY)
                fd.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
