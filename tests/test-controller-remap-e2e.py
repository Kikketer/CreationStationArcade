#!/usr/bin/env python3
"""Optional kernel-level test for arcade-input-remap.py.

Runs only when the current user can create uinput devices. Uses a virtual
source controller, so no cabinet hardware is needed.
"""

import glob
import json
import os
import select
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
    skip("requires root and a writable /dev/uinput")

try:
    import uinput
    from evdev import InputDevice, ecodes
except ImportError as exc:
    skip(f"missing dependency: {exc}")


def find_event(name):
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_path, encoding="utf-8") as f:
                if f.read().strip() == name:
                    event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
                    return os.path.join("/dev/input", event)
        except OSError:
            pass
    return None


def read_key_events(device, seconds=2):
    seen = []
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([device.fd], [], [], 0.2)
        if not ready:
            continue
        try:
            events = device.read()
        except BlockingIOError:
            continue
        for event in events:
            if event.type == ecodes.EV_KEY:
                seen.append((event.code, event.value))
    return seen


def main():
    hat = uinput.ABS_HAT0X + (-1, 1, 0, 0)
    source = uinput.Device([uinput.KEY_R, hat], name="CSA Remap Test Source")
    time.sleep(0.5)
    source_path = find_event("CSA Remap Test Source")
    if not source_path:
        source.destroy()
        raise RuntimeError("virtual source device did not appear")

    fd, config_path = tempfile.mkstemp()
    os.close(fd)
    config = {
        "version": 1,
        "players": [{
            "player": 1,
            "controls": {
                "a": {"device": source_path, "type": "key", "code": uinput.KEY_R[1]},
                "left": {
                    "device": source_path,
                    "type": "abs",
                    "code": uinput.ABS_HAT0X[1],
                    "direction": -1,
                    "threshold": 1,
                },
            },
        }],
    }
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f)

    env = dict(os.environ, ARCADE_CONTROLLER_MAP=config_path)
    proc = subprocess.Popen(
        ["python3", str(ROOT / "install" / "arcade-input-remap.py")],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    output = None
    try:
        output_path = None
        for _ in range(30):
            output_path = find_event("Creation Station Calibrated Input")
            if output_path or proc.poll() is not None:
                break
            time.sleep(0.2)
        if not output_path:
            raise RuntimeError("calibrated virtual keyboard did not appear")

        # Give the service a moment to open/grab the source after creating the output.
        time.sleep(1)
        output = InputDevice(output_path)
        os.set_blocking(output.fd, False)

        source.emit(uinput.KEY_R, 1)
        key_events = read_key_events(output)
        if (uinput.KEY_Q[1], 1) not in key_events or (uinput.KEY_Z[1], 1) not in key_events:
            raise AssertionError(f"missing aliased button output: {key_events}")
        source.emit(uinput.KEY_R, 0)
        read_key_events(output, seconds=0.4)

        source.emit(uinput.ABS_HAT0X, -1)
        axis_events = read_key_events(output)
        if (uinput.KEY_A[1], 1) not in axis_events or (uinput.KEY_LEFT[1], 1) not in axis_events:
            raise AssertionError(f"missing aliased axis output: {axis_events}")
        source.emit(uinput.ABS_HAT0X, 0)

        print("controller remapper kernel-level test passed")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        if output is not None:
            output.close()
        source.destroy()
        try:
            os.remove(config_path)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
