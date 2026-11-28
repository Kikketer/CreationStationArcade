#!/usr/bin/env python3
"""Unit tests for the controller remapper's pure mapping logic."""

import importlib.util
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

evdev = types.ModuleType("evdev")
evdev.ecodes = types.SimpleNamespace(EV_KEY=1, EV_ABS=3)
evdev.InputDevice = object
sys.modules["evdev"] = evdev

uinput = types.ModuleType("uinput")
KEY_NAMES = [
    "KEY_W", "KEY_UP", "KEY_S", "KEY_DOWN", "KEY_A", "KEY_LEFT",
    "KEY_D", "KEY_RIGHT", "KEY_Q", "KEY_Z", "KEY_E", "KEY_X",
    "KEY_ESC", "KEY_I", "KEY_K", "KEY_J", "KEY_L", "KEY_U", "KEY_O",
]
for index, name in enumerate(KEY_NAMES, start=1):
    setattr(uinput, name, (1, index))
sys.modules["uinput"] = uinput

spec = importlib.util.spec_from_file_location("remap", ROOT / "install" / "arcade-input-remap.py")
remap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remap)


def test_build_index():
    config = {
        "players": [
            {
                "player": 1,
                "controls": {
                    "up": {"device": "/dev/input/by-path/p1", "type": "key", "code": 30},
                    "left": {
                        "device": "/dev/input/by-path/p1",
                        "type": "abs",
                        "code": 0,
                        "direction": -1,
                        "threshold": 1,
                    },
                },
            }
        ]
    }
    index = remap.build_index(config)
    entries = index["/dev/input/by-path/p1"]
    assert ("key", 30, 0, remap.AXIS_THRESHOLD) in [entry[0] for entry in entries]
    assert ("abs", 0, -1, 1) in [entry[0] for entry in entries]
    assert [entry[1:] for entry in entries] == [(1, "up"), (1, "left")]


def test_key_events_are_unique():
    events = remap.key_events()
    assert len(events) == len(set(events))
    assert (1, KEY_NAMES.index("KEY_ESC") + 1) in events


def test_emit_action_aliases_and_state():
    class Output:
        def __init__(self):
            self.calls = []

        def emit(self, key, value, syn=True):
            self.calls.append((key, value, syn))

    out = Output()
    active = {}
    assert remap.emit_action(out, 1, "up", True, active)
    assert len(out.calls) == 2
    assert all(value == 1 for _, value, _ in out.calls)
    assert not remap.emit_action(out, 1, "up", True, active)
    assert remap.emit_action(out, 1, "up", False, active)
    assert len(out.calls) == 4
    assert all(value == 0 for _, value, _ in out.calls[2:])


if __name__ == "__main__":
    test_build_index()
    test_key_events_are_unique()
    test_emit_action_aliases_and_state()
    print("controller remapper tests passed")
