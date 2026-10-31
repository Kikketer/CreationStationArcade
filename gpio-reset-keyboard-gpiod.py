#!/usr/bin/env python3
# gpio-reset-keyboard-gpiod.py — cabinet reset/exit button helper.
#
# Two modes:
#   default            -> uinput 'r' key (soft reset, the Game handles it)
#   --pidfile PATH     -> SIGKILL the pid in PATH (hard exit to menu,
#                         works even on a hung game)
#
# Works with both libgpiod v1 (bookworm, La Frite) and v2 (trixie, Pi OS).
import os
import sys
import time
import struct
import fcntl
import argparse
import signal

import gpiod

LOG_FILE = os.environ.get("ARCADE_LOG", "/home/pi/arcade.log")
UINPUT_PATH = "/dev/uinput"
DEFAULT_CHIP = "/dev/gpiochip0"
DEFAULT_PIN = os.environ.get("GPIO_RESET_PIN", "14")

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


# --- GPIO backend: uniform interface over libgpiod v1 and v2 ---

GPIOD_V2 = hasattr(gpiod, "LineSettings")


class LineWatcher:
    """Request one GPIO line as input (with bias) and read its level."""
    def __init__(self, chip_path, spec, active_low):
        self.active_low = active_low
        if GPIOD_V2:
            from gpiod.line import Direction, Bias
            chip = gpiod.Chip(chip_path)
            try:
                offset = int(spec)
            except ValueError:
                offset = chip.line_info_from_name(spec).offset
            settings = gpiod.LineSettings(
                direction=Direction.INPUT,
                bias=Bias.PULL_UP if active_low else Bias.PULL_DOWN,
            )
            self._req = chip.request_lines(
                consumer="gpio-reset-keyboard",
                config={offset: settings},
            )
            self._offset = offset
            self._line = None
            self._chip = chip
        else:
            self._chip = gpiod.Chip(chip_path)
            try:
                offset = int(spec)
                self._line = self._chip.get_line(offset)
            except ValueError:
                self._line = self._chip.find_line(spec)
                if self._line is None:
                    raise ValueError(f"GPIO line not found: {spec}")
            flags = 0
            if active_low:
                if hasattr(gpiod, "LINE_REQ_FLAG_BIAS_PULL_UP"):
                    flags |= gpiod.LINE_REQ_FLAG_BIAS_PULL_UP
            else:
                if hasattr(gpiod, "LINE_REQ_FLAG_BIAS_PULL_DOWN"):
                    flags |= gpiod.LINE_REQ_FLAG_BIAS_PULL_DOWN
            self._line.request(
                consumer="gpio-reset-keyboard",
                type=gpiod.LINE_REQ_DIR_IN,
                flags=flags,
            )
            self._req = None

    def value(self):
        if GPIOD_V2:
            from gpiod.line import Value
            return 1 if self._req.get_value(self._offset) == Value.ACTIVE else 0
        return self._line.get_value()

    def release(self):
        if GPIOD_V2:
            try:
                self._req.release()
            except Exception:
                pass
            try:
                self._chip.close()
            except Exception:
                pass
        else:
            try:
                self._line.release()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chip", default=DEFAULT_CHIP)
    parser.add_argument("--pin", default=DEFAULT_PIN)
    parser.add_argument("--active-low", action="store_true")
    parser.add_argument("--pidfile", default=os.environ.get("GPIO_RESET_PIDFILE", ""),
                        help="kill the pid in this file instead of injecting an 'r' key")
    args = parser.parse_args()

    chip_path = args.chip
    if not chip_path.startswith("/dev/"):
        chip_path = f"/dev/{chip_path}"
    pin_spec = args.pin
    active_low = args.active_low
    debounce_s = 0.05

    log(f"Starting: chip={chip_path} pin={pin_spec} active_low={active_low} "
        f"pidfile={args.pidfile or '<none>'} gpiod_v={'2' if GPIOD_V2 else '1'}")
    fd = None if args.pidfile else create_vkbd()

    watcher = LineWatcher(chip_path, pin_spec, active_low)
    active = 0 if active_low else 1

    try:
        last = None
        while True:
            state = watcher.value()
            if last is None:
                log(f"Initial GPIO state on {pin_spec}: {state}")
            elif state != last:
                log(f"GPIO state changed on {pin_spec}: {last} -> {state}")
            if state == active and last != active:
                time.sleep(debounce_s)
                if watcher.value() == active:
                    if args.pidfile:
                        archive_request()
                        kill_pidfile(args.pidfile)
                    else:
                        send_r(fd)
            last = state
            time.sleep(0.01)
    finally:
        watcher.release()
        if fd is not None:
            try:
                fcntl.ioctl(fd, UI_DEV_DESTROY)
                fd.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
