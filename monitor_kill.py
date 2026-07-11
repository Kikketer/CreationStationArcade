import RPi.GPIO as GPIO
import time
import subprocess
import os

LOG_FILE = "/home/pi/arcade.log"

RESET_PIN = 3       # BCM 3 — active HIGH, pull-down
DEBOUNCE_MS = 500

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GAME_NAME = os.environ.get("SINGLE_GAME_NAME", "AndyPaddleTheRiver")
GAME_ELF = os.path.join(SCRIPT_DIR, "games", f"{GAME_NAME}.elf")


def _log(msg: str) -> None:
    print(msg)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception:
        pass


def _get_game_process_name() -> str:
    """Read /tmp/pxt-pid written by the MCA ELF runtime, return process name."""
    try:
        with open("/tmp/pxt-pid", "r") as f:
            pid = f.readline().strip()
        if not pid:
            return ""
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except (OSError, ValueError):
        return ""


def _kill_elf() -> None:
    _log("Reset pressed — killing ELF...")
    name = _get_game_process_name()
    if name:
        subprocess.run(["killall", "-9", name], check=False)
        _log(f"killall -9 {name}")
    else:
        subprocess.run(["pkill", "-9", "-f", r"\.elf"], check=False)
        _log("pkill -9 -f .elf (fallback)")


def _relaunch() -> None:
    launcher = os.path.join(SCRIPT_DIR, "launcher.sh")
    _log(f"Relaunching: {launcher}")
    if not os.path.exists(launcher):
        _log(f"ERROR: launcher.sh not found at {launcher}")
        return
    env = os.environ.copy()
    env["SINGLE_GAME_NAME"] = GAME_NAME
    subprocess.Popen(
        ["bash", launcher],
        cwd=SCRIPT_DIR,
        env=env,
    )


def on_reset(channel):
    _kill_elf()
    time.sleep(1)
    _relaunch()


def main():
    _log(f"=== monitor_kill.py start: game={GAME_NAME}, pin={RESET_PIN} ===")
    try:
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(RESET_PIN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        GPIO.add_event_detect(RESET_PIN, GPIO.RISING, callback=on_reset, bouncetime=DEBOUNCE_MS)
        _log(f"Monitoring BCM pin {RESET_PIN} (active HIGH) for reset...")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        _log("monitor_kill.py exiting.")
    finally:
        GPIO.cleanup()


if __name__ == "__main__":
    main()
