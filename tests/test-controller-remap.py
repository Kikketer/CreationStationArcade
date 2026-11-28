#!/usr/bin/env python3
"""Unit tests for the controller remapper's pure mapping logic."""

import importlib.util
import struct
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

evdev = types.ModuleType("evdev")
evdev.ecodes = types.SimpleNamespace(EV_KEY=1, EV_ABS=3)
evdev.InputDevice = object
sys.modules["evdev"] = evdev

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


def test_hid_report_layout():
    assert len(remap.HID_REPORT_DESCRIPTOR) == 80
    report = remap.hid_report(0b101, 7)
    assert len(report) == 15
    buttons, x, y, z, rx, ry, rz, hat = struct.unpack("<H6hB", report)
    assert buttons == 0b101
    assert (x, y, rx, ry) == (0, 0, 0, 0)
    assert (z, rz) == (remap.TRIGGER_REST, remap.TRIGGER_REST)
    assert hat == 7


def test_hat_values():
    assert remap.hat_value(set()) == 0
    assert remap.hat_value({"up"}) == 1
    assert remap.hat_value({"up", "right"}) == 2
    assert remap.hat_value({"right"}) == 3
    assert remap.hat_value({"down", "right"}) == 4
    assert remap.hat_value({"down"}) == 5
    assert remap.hat_value({"down", "left"}) == 6
    assert remap.hat_value({"left"}) == 7
    assert remap.hat_value({"up", "left"}) == 8


def test_uhid_gamepad_state_updates():
    pad = object.__new__(remap.UhidGamepad)
    pad.buttons = 0
    pad.directions = set()
    sent = []
    pad.send_report = lambda: sent.append((pad.buttons, remap.hat_value(pad.directions)))

    pad.set_action("a", True)
    assert sent[-1] == (1, 0)
    pad.set_action("reset", True)
    assert sent[-1] == (1 | (1 << 2) | (1 << 6) | (1 << 7), 0)
    pad.set_action("left", True)
    assert sent[-1][1] == 7
    pad.set_action("up", True)
    assert sent[-1][1] == 8
    pad.set_action("left", False)
    assert sent[-1][1] == 1
    pad.set_action("a", False)
    assert sent[-1][0] == (1 << 2) | (1 << 6) | (1 << 7)


def test_emit_action_tracks_state():
    class Output:
        def __init__(self):
            self.calls = []

        def set_action(self, action, pressed, button_bits=None):
            self.calls.append((action, pressed, button_bits))

    class Keyboard:
        def __init__(self):
            self.calls = []

        def set_pressed(self, pressed):
            self.calls.append(pressed)

    out = Output()
    keyboard = Keyboard()
    outputs = {1: out}
    active = {}
    assert remap.emit_action(outputs, 1, "up", True, active)
    assert out.calls == [("up", True, None)]
    assert not remap.emit_action(outputs, 1, "up", True, active)
    assert remap.emit_action(outputs, 1, "up", False, active)
    assert out.calls == [("up", True, None), ("up", False, None)]

    assert remap.emit_action(outputs, 1, "reset", True, active, keyboard, "native")
    assert keyboard.calls == [True]
    assert out.calls[-1] == ("reset", True, ())
    assert remap.emit_action(outputs, 1, "reset", False, active, keyboard, "native")
    assert keyboard.calls == [True, False]
    assert out.calls[-1] == ("reset", False, ())


def test_reset_output_modes():
    assert remap.reset_button_bits("chromium") == (6, 7)
    assert remap.reset_button_bits("native") == ()
    assert remap.reset_button_bits("elf") == (2,)
    assert remap.reset_button_bits("") == (2, 6, 7)


def test_config_has_reset():
    assert remap.config_has_reset({"players": [{"controls": {"reset": {"type": "key"}}}]})
    assert not remap.config_has_reset({"players": [{"controls": {"a": {"type": "key"}}}]})


if __name__ == "__main__":
    test_build_index()
    test_hid_report_layout()
    test_hat_values()
    test_uhid_gamepad_state_updates()
    test_emit_action_tracks_state()
    test_reset_output_modes()
    test_config_has_reset()
    print("controller remapper tests passed")
