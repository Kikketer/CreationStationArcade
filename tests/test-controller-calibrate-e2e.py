#!/usr/bin/env python3
"""Optional kernel-level end-to-end test for the calibration wizard.

Requires root and a writable /dev/uinput. The test creates a virtual keyboard
source, captures one input, skips the next control with Esc, then finishes
early with f and validates the generated calibration JSON.
"""

import json
import os
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
    import pexpect
    import uinput
except ImportError as exc:
    skip(f"missing test dependency: {exc}")


def main():
    output_file = tempfile.NamedTemporaryFile(delete=False)
    output_file.close()
    os.unlink(output_file.name)

    source = uinput.Device([uinput.KEY_R], name="CSA Calibration Test Source")
    time.sleep(0.5)
    child = pexpect.spawn(
        sys.executable,
        [str(ROOT / "install" / "controller-calibrate.py"), "1", output_file.name],
        cwd=str(ROOT),
        timeout=8,
        encoding="utf-8",
        env=dict(os.environ, ARCADE_ENGINE="native"),
    )
    try:
        child.expect("Player 1: press UP")
        source.emit(uinput.KEY_R, 1, syn=True)
        time.sleep(0.1)
        source.emit(uinput.KEY_R, 0, syn=True)
        child.expect("captured on CSA Calibration Test Source")

        child.expect("Player 1: press DOWN")
        child.send("\x1b")
        child.expect("skipped")

        child.expect("Player 1: press LEFT")
        child.send("f")
        child.expect("Saved calibration")
        child.expect(pexpect.EOF)

        with open(output_file.name, encoding="utf-8") as f:
            data = json.load(f)
        player = data["players"][0]
        control = player["controls"]["up"]
        assert data["engine"] == "native"
        assert control["type"] == "key"
        assert control["code"] == uinput.KEY_R[1]
        assert control["sourceName"] == "CSA Calibration Test Source"
        assert "down" not in player["controls"]
        assert "left" not in player["controls"]
        assert "down" in player["skipped"]
        assert player["finishedEarly"] is True
        print("controller calibration kernel-level test passed")
    finally:
        if child.isalive():
            child.close(force=True)
        source.destroy()
        try:
            os.unlink(output_file.name)
        except OSError:
            pass


if __name__ == "__main__":
    main()
