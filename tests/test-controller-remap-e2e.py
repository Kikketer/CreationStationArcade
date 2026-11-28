#!/usr/bin/env python3
"""Optional kernel-level end-to-end test for the controller remapper.

This requires root and a writable /dev/uinput. It creates a virtual source
controller, runs the real remap daemon against a temporary calibration file,
and verifies that source key/axis events become standard gamepad events on the
calibrated Player 1 virtual gamepad.
"""

import glob
import json
import os
import select
import selectors
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def skip(reason):
    print(f"SKIP: {reason}")
    sys.exit(0)


if os.geteuid() != 0 or not os.path.exists("/dev/uinput") or not os.access("/dev/uinput", os.W_OK):
    skip("requires root and a writable /dev/uinput for the test source")
if not os.path.exists("/dev/uhid") or not os.access("/dev/uhid", os.W_OK):
    skip("requires a writable /dev/uhid for virtual gamepads")

try:
    from evdev import InputDevice, ecodes
    import uinput
except ImportError as exc:
    skip(f"missing input dependencies: {exc}")


def find_event_by_name(name):
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            if Path(name_path).read_text(encoding="utf-8").strip() == name:
                event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
                return os.path.join("/dev/input", event)
        except OSError:
            pass
    return None


def wait_for_event(name, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        path = find_event_by_name(name)
        if path:
            return path
        time.sleep(0.1)
    raise AssertionError(f"virtual input device did not appear: {name}")


def drain(device):
    while True:
        try:
            for _event in device.read():
                pass
        except BlockingIOError:
            return


def read_events(device, timeout=1.5):
    selector = selectors.DefaultSelector()
    selector.register(device, selectors.EVENT_READ)
    result = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready = selector.select(timeout=max(0, deadline - time.time()))
        if not ready:
            break
        try:
            result.extend((event.type, event.code, event.value) for event in device.read())
        except BlockingIOError:
            pass
    return result


def joystick_path_for_event(event_path):
    sysfs_device = os.path.realpath(os.path.join("/sys/class/input", os.path.basename(event_path), "device"))
    joysticks = sorted(glob.glob(os.path.join(sysfs_device, "js*")))
    if not joysticks:
        raise AssertionError(f"no joystick node for {event_path}")
    return os.path.join("/dev/input", os.path.basename(joysticks[0]))


def read_js_events(fd, timeout=1.5):
    result = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _w, _x = select.select([fd], [], [], max(0, deadline - time.time()))
        if not ready:
            break
        try:
            data = os.read(fd, 8)
        except BlockingIOError:
            continue
        if len(data) < 8:
            break
        result.append(struct.unpack("IhBB", data))
    return result


def drain_js(fd):
    while True:
        try:
            if len(os.read(fd, 8)) < 8:
                return
        except BlockingIOError:
            return


def main():
    hat = uinput.ABS_HAT0X + (-1, 1, 0, 0)
    source = uinput.Device([uinput.KEY_R, hat], name="CSA Remap Test Source")
    time.sleep(0.5)
    source_path = wait_for_event("CSA Remap Test Source")

    config = {
        "version": 1,
        "owner": "root",
        "players": [
            {
                "player": 1,
                "controls": {
                    "a": {"device": source_path, "type": "key", "code": ecodes.KEY_R},
                    "left": {
                        "device": source_path,
                        "type": "abs",
                        "code": ecodes.ABS_HAT0X,
                        "direction": -1,
                        "threshold": 1,
                    },
                },
                "skipped": [],
                "finishedEarly": False,
            }
        ],
    }
    config_file = tempfile.NamedTemporaryFile("w", delete=False)
    json.dump(config, config_file)
    config_file.close()

    env = dict(os.environ)
    env["ARCADE_CONTROLLER_MAP"] = config_file.name
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "install" / "arcade-input-remap.py")],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    output = None
    js_fd = None
    try:
        output_path = wait_for_event("Creation Station Player 1")
        output = InputDevice(output_path)
        os.set_blocking(output.fd, False)
        js_fd = os.open(joystick_path_for_event(output_path), os.O_RDONLY | os.O_NONBLOCK)
        # Give the daemon time to open/grab the source before injecting input.
        time.sleep(1)
        drain(output)
        drain_js(js_fd)

        source.emit(uinput.KEY_R, 1, syn=True)
        key_events = read_events(output)
        if (ecodes.EV_KEY, ecodes.BTN_A, 1) not in key_events:
            raise AssertionError(f"missing virtual A output: {key_events}")
        js_key_events = read_js_events(js_fd)
        if not any(kind == 1 and number == 0 and value == 1 for _time, value, kind, number in js_key_events):
            raise AssertionError(f"missing joystick A output: {js_key_events}")
        source.emit(uinput.KEY_R, 0, syn=True)
        release_events = read_events(output)
        if (ecodes.EV_KEY, ecodes.BTN_A, 0) not in release_events:
            raise AssertionError(f"missing virtual A release: {release_events}")

        source.emit(uinput.ABS_HAT0X, -1, syn=True)
        axis_events = read_events(output)
        if (ecodes.EV_ABS, ecodes.ABS_HAT0X, -1) not in axis_events:
            raise AssertionError(f"missing virtual left hat output: {axis_events}")
        js_axis_events = read_js_events(js_fd)
        if not any(kind == 2 and number == 6 and value < -10000 for _time, value, kind, number in js_axis_events):
            raise AssertionError(f"missing joystick left axis output: {js_axis_events}")

        print("controller remapper kernel-level test passed")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
        if output is not None:
            output.close()
        if js_fd is not None:
            os.close(js_fd)
        source.destroy()
        try:
            os.unlink(config_file.name)
        except OSError:
            pass


if __name__ == "__main__":
    main()
