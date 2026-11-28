#!/usr/bin/env python3
"""Translate calibrated cabinet inputs into a MakeCode-friendly keyboard.

The service reads /etc/arcade-controller-map.json, grabs those physical input
devices, and emits standard MakeCode keyboard controls through one virtual
keyboard. Player 1 also emits the menu-friendly arrow/Z/X aliases.
"""

import glob
import json
import os
import selectors
import sys
import time

try:
    from evdev import InputDevice, ecodes
    import uinput
except ImportError as exc:
    print(f"ERROR: missing input dependency: {exc}", file=sys.stderr)
    sys.exit(2)

CONFIG = os.environ.get("ARCADE_CONTROLLER_MAP", "/etc/arcade-controller-map.json")
LINK_PATH = "/dev/input/arcade-calibrated"
AXIS_THRESHOLD = 8000

# MakeCode Arcade keyboard controls. Player 1 has two aliases for each action:
# WASD/QE are the documented game controls; arrows/Z/X drive the Chromium menu.
PLAYER_KEYS = {
    1: {
        "up": ["KEY_W", "KEY_UP"],
        "down": ["KEY_S", "KEY_DOWN"],
        "left": ["KEY_A", "KEY_LEFT"],
        "right": ["KEY_D", "KEY_RIGHT"],
        "a": ["KEY_Q", "KEY_Z"],
        "b": ["KEY_E", "KEY_X"],
        "reset": ["KEY_ESC"],
    },
    2: {
        "up": ["KEY_I"],
        "down": ["KEY_K"],
        "left": ["KEY_J"],
        "right": ["KEY_L"],
        "a": ["KEY_U"],
        "b": ["KEY_O"],
        "reset": ["KEY_ESC"],
    },
}


def key_events():
    events = []
    seen = set()
    for mapping in PLAYER_KEYS.values():
        for names in mapping.values():
            for name in names:
                key = getattr(uinput, name)
                if key not in seen:
                    events.append(key)
                    seen.add(key)
    return events


def load_config(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: calibration file not found: {path}", file=sys.stderr)
        return None
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid calibration file {path}: {exc}", file=sys.stderr)
        return None
    if not data.get("players"):
        print(f"ERROR: calibration file has no players: {path}", file=sys.stderr)
        return None
    return data


def build_index(config):
    by_device = {}
    for player in config.get("players", []):
        player_num = int(player.get("player", 0))
        if player_num not in PLAYER_KEYS:
            continue
        for action, control in player.get("controls", {}).items():
            if action not in PLAYER_KEYS[player_num]:
                continue
            device = control.get("device")
            if not device:
                continue
            key = (
                control.get("type"),
                int(control.get("code", -1)),
                int(control.get("direction", 0)),
                int(control.get("threshold", AXIS_THRESHOLD)),
            )
            by_device.setdefault(device, []).append((key, player_num, action))
    return by_device


def open_device(path):
    try:
        dev = InputDevice(path)
        try:
            dev.grab()
        except OSError:
            pass
        return dev
    except (OSError, PermissionError):
        return None


def find_virtual_event():
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_path, encoding="utf-8") as f:
                if f.read().strip() == "Creation Station Calibrated Input":
                    event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
                    return os.path.join("/dev/input", event)
        except OSError:
            pass
    return None


def publish_device_link():
    event = find_virtual_event()
    if not event:
        return
    try:
        os.remove(LINK_PATH)
    except FileNotFoundError:
        pass
    try:
        os.symlink(event, LINK_PATH)
    except OSError:
        pass


def emit(out, key, pressed):
    out.emit(key, 1 if pressed else 0, syn=True)


def emit_action(out, player, action, pressed, active):
    changed = False
    for name in PLAYER_KEYS[player][action]:
        key = getattr(uinput, name)
        state_key = (player, action, name)
        if active.get(state_key) != pressed:
            emit(out, key, pressed)
            active[state_key] = pressed
            changed = True
    return changed


def main():
    config = load_config(CONFIG)
    if config is None:
        return 1
    index = build_index(config)
    if not index:
        print("ERROR: calibration file has no usable controls", file=sys.stderr)
        return 1

    out = uinput.Device(key_events(), name="Creation Station Calibrated Input", vendor=0x1209, product=0xCAFE)
    time.sleep(0.5)
    publish_device_link()

    devices = {}
    selector = selectors.DefaultSelector()
    active = {}
    axis_state = {}

    print("Creation Station input remapper running", flush=True)
    while True:
        # Open missing configured devices. This simple retry loop also handles
        # controllers plugged in after boot.
        for path in index:
            if path not in devices:
                dev = open_device(path)
                if dev:
                    devices[path] = dev
                    selector.register(dev, selectors.EVENT_READ, path)
                    print(f"opened {path} ({dev.name})", flush=True)

        if not devices:
            time.sleep(2)
            continue

        events = selector.select(timeout=2)
        if not events:
            continue
        for key_obj, _ in events:
            path = key_obj.data
            dev = key_obj.fileobj
            try:
                batch = dev.read()
            except OSError:
                for (_kind, _code, _direction, _threshold), player, action in index.get(path, []):
                    emit_action(out, player, action, False, active)
                try:
                    selector.unregister(dev)
                except Exception:
                    pass
                try:
                    dev.close()
                except Exception:
                    pass
                devices.pop(path, None)
                continue

            for event in batch:
                for (kind, code, direction, threshold), player, action in index.get(path, []):
                    if kind == "key" and event.type == ecodes.EV_KEY and event.code == code:
                        if event.value == 1:
                            emit_action(out, player, action, True, active)
                        elif event.value == 0:
                            emit_action(out, player, action, False, active)
                    elif kind == "abs" and event.type == ecodes.EV_ABS and event.code == code:
                        pressed = (event.value * direction) >= threshold
                        state_key = (path, code, direction, player, action)
                        if axis_state.get(state_key) != pressed:
                            axis_state[state_key] = pressed
                            emit_action(out, player, action, pressed, active)


if __name__ == "__main__":
    sys.exit(main())
