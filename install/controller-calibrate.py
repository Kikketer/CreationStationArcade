#!/usr/bin/env python3
"""Guided USB controller calibration for Creation Station Arcade.

Writes /etc/arcade-controller-map.json. The file describes physical evdev
inputs; arcade-input-remap.py turns them into MakeCode-friendly virtual keys.
"""

import glob
import json
import os
import select
import sys
import termios
import time
import tty
from datetime import datetime, timezone

try:
    from evdev import InputDevice, ecodes
except ImportError:
    print("ERROR: python3-evdev is not installed", file=sys.stderr)
    sys.exit(2)

ACTIONS = ["up", "down", "left", "right", "a", "b", "reset"]
LABELS = {
    "up": "UP",
    "down": "DOWN",
    "left": "LEFT",
    "right": "RIGHT",
    "a": "A",
    "b": "B",
    "reset": "RESET / EXIT",
}
AXIS_THRESHOLD = 8000


def by_path_for(path):
    real = os.path.realpath(path)
    for link in sorted(glob.glob("/dev/input/by-path/*")):
        if os.path.realpath(link) == real:
            return link
    return path


def open_devices():
    devices = []
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            dev = InputDevice(path)
            if dev.name == "Creation Station Calibrated Input":
                dev.close()
                continue
            os.set_blocking(dev.fd, False)
            devices.append(dev)
        except (OSError, PermissionError):
            pass
    return devices


def set_cbreak(fd):
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    return old


def restore_tty(fd, old):
    termios.tcsetattr(fd, termios.TCSADRAIN, old)


def drain_devices(fds):
    while True:
        ready, _, _ = select.select(list(fds), [], [], 0)
        if not ready:
            return
        for fd in ready:
            try:
                while os.read(fd, 4096):
                    pass
            except (BlockingIOError, OSError):
                pass


def capture_action(devices, fd_tty, player, action):
    label = LABELS[action]
    print(f"\nPlayer {player}: press {label}")
    print("  Esc = skip this input, f = finish calibration early, 20s timeout")
    sys.stdout.flush()

    fd_to_dev = {dev.fd: dev for dev in devices}
    deadline = time.monotonic() + 20
    drain_devices(fd_to_dev)

    while time.monotonic() < deadline:
        timeout = max(0.1, deadline - time.monotonic())
        # Read terminal control keys before evdev so Esc/f are not captured as cabinet input.
        fds = [fd_tty] + list(fd_to_dev)
        ready, _, _ = select.select(fds, [], [], min(0.25, timeout))
        for fd in ready:
            if fd == fd_tty:
                try:
                    data = os.read(fd_tty, 8)
                except OSError:
                    data = b""
                if b"\x1b" in data:
                    print("  skipped")
                    return None, False
                if b"f" in data.lower():
                    print("  finishing early")
                    return None, True
                continue

            dev = fd_to_dev[fd]
            try:
                events = dev.read()
            except (BlockingIOError, OSError):
                continue
            for event in events:
                if event.type == ecodes.EV_KEY and event.value == 1:
                    # Escape is reserved as the calibration control key.
                    if event.code == ecodes.KEY_ESC:
                        print("  skipped")
                        return None, False
                    return {
                        "device": by_path_for(dev.path),
                        "type": "key",
                        "code": event.code,
                        "sourceName": dev.name,
                    }, False
                if event.type == ecodes.EV_ABS:
                    hat = event.code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y)
                    if abs(event.value) >= AXIS_THRESHOLD or (hat and event.value != 0):
                        return {
                            "device": by_path_for(dev.path),
                            "type": "abs",
                            "code": event.code,
                            "direction": 1 if event.value > 0 else -1,
                            "threshold": max(1, abs(event.value) // 2),
                            "sourceName": dev.name,
                        }, False

    print("  timed out; skipped")
    return None, False


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} PLAYER_COUNT OUTPUT_JSON", file=sys.stderr)
        return 2
    try:
        player_count = int(sys.argv[1])
    except ValueError:
        return 2
    if not 1 <= player_count <= 2:
        print("ERROR: this calibration layer currently supports 1 or 2 players", file=sys.stderr)
        return 2
    output = sys.argv[2]

    devices = open_devices()
    if not devices:
        print("ERROR: no readable /dev/input/event* devices found", file=sys.stderr)
        return 2

    try:
        fd_tty = os.open("/dev/tty", os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        print("ERROR: calibration needs an interactive terminal", file=sys.stderr)
        return 2

    print("\n=== Controller calibration ===")
    print("Use the actual cabinet controls. Escape skips one input; lowercase f finishes early.")
    print("Keyboards, keyboard encoders, joystick buttons, and joystick axes are supported.")

    old = set_cbreak(fd_tty)
    result = {
        "version": 1,
        "created": datetime.now(timezone.utc).isoformat(),
        "players": [],
    }
    finish = False
    try:
        for player in range(1, player_count + 1):
            if finish:
                break
            entry = {"player": player, "controls": {}}
            for action in ACTIONS:
                while True:
                    control, finish = capture_action(devices, fd_tty, player, action)
                    if finish or control is None:
                        break
                    signature = (
                        control["device"], control["type"], control["code"],
                        control.get("direction", 0),
                    )
                    duplicate = any(
                        (
                            existing["device"], existing["type"], existing["code"],
                            existing.get("direction", 0),
                        ) == signature
                        for existing in entry["controls"].values()
                    )
                    if not duplicate:
                        break
                    print("  that input is already assigned for this player; use a different control")
                if control:
                    entry["controls"][action] = control
                    print(f"  captured on {control['sourceName']} ({control['device']})")
                if finish:
                    break
            if entry["controls"]:
                result["players"].append(entry)
    finally:
        restore_tty(fd_tty, old)
        os.close(fd_tty)
        for dev in devices:
            try:
                dev.close()
            except Exception:
                pass

    tmp = output + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    os.replace(tmp, output)
    print(f"\nSaved calibration: {output}")
    return 0 if result["players"] else 1


if __name__ == "__main__":
    sys.exit(main())
