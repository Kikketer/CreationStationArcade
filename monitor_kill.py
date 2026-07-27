#!/usr/bin/env python3
"""Reset monitor for the single native MakeCode Arcade kiosk.

Watches the reset button defined by BTN_RESET in arcade.cfg (default BCM 4) and
kills the running native Game process. launcher.sh then restarts the game.
"""

import os
import subprocess
import sys
import time

LOG_FILE = "/home/pi/arcade.log"
ARCADE_CFG = "/home/pi/CreationStationArcade/arcade.cfg"
PIDFILE = "/tmp/creationstation_current_game.pid"


def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_reset_pin(default: int = 4) -> int:
    try:
        with open(ARCADE_CFG, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key.strip() == "BTN_RESET":
                    return int(value.strip())
    except Exception as e:
        log(f"WARNING: could not read {ARCADE_CFG}: {e}; using default {default}")
    return default


def kill_game() -> None:
    log("Reset button pressed")
    pid = None
    try:
        if os.path.exists(PIDFILE):
            with open(PIDFILE, "r") as f:
                pid = f.read().strip()
    except Exception as e:
        log(f"WARNING: could not read {PIDFILE}: {e}")

    if pid and pid.isdigit():
        try:
            os.kill(int(pid), 9)
            log(f"Killed Game pid {pid}")
            return
        except ProcessLookupError:
            log(f"PID {pid} not found, falling back to pkill")
        except Exception as e:
            log(f"ERROR killing pid {pid}: {e}")

    # Fallback: kill any Game binary inside a games/<name>/ directory.
    result = subprocess.run(
        ["pkill", "-9", "-f", r"games/[^/]+/Game"],
        capture_output=True,
    )
    log(f"Fallback pkill status: {result.returncode}")


def main() -> None:
    reset_pin = load_reset_pin()
    log(f"Monitoring reset button on BCM {reset_pin}")

    try:
        import RPi.GPIO as GPIO  # type: ignore

        GPIO.setmode(GPIO.BCM)
        GPIO.setup(reset_pin, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        GPIO.add_event_detect(
            reset_pin,
            GPIO.RISING,
            callback=lambda _: kill_game(),
            bouncetime=500,
        )

        while True:
            time.sleep(1)
    except ImportError:
        log("ERROR: RPi.GPIO not installed; reset monitor cannot run")
        sys.exit(1)
    except Exception as e:
        log(f"ERROR in reset monitor: {e}")
        raise
    finally:
        try:
            GPIO.cleanup()  # type: ignore
        except Exception:
            pass


if __name__ == "__main__":
    main()
