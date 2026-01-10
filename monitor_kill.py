import RPi.GPIO as GPIO
import time
import subprocess

ARCADE_CFG_PATH = "/home/pi/CreationStationArcade/arcade.cfg"

# Configuration
KILL_PIN = 4  # BCM 4
INACTIVITY_SECONDS = 5 * 60

_last_activity = None


def _now() -> float:
    return time.monotonic()


def _load_button_pins(cfg_path: str) -> list[int]:
    pins: list[int] = []
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()

                if key in {"BTN_RESET", "BTN_EXIT"}:
                    continue

                if not key.startswith("BTN_"):
                    continue

                try:
                    pin = int(value)
                except ValueError:
                    continue

                if pin == KILL_PIN:
                    continue

                pins.append(pin)
    except FileNotFoundError:
        print(f"WARNING: arcade.cfg not found at {cfg_path}. Inactivity timer will not work.")
    except Exception as e:
        print(f"WARNING: Failed reading {cfg_path}: {e}. Inactivity timer will not work.")

    # De-dupe while preserving order
    seen: set[int] = set()
    deduped: list[int] = []
    for p in pins:
        if p in seen:
            continue
        seen.add(p)
        deduped.append(p)
    return deduped


def _is_non_menu_elf_running() -> bool:
    try:
        result = subprocess.run(
            ["pgrep", "-af", r"\.elf"],
            check=False,
            capture_output=True,
            text=True,
        )
        lines = [proc_line.strip() for proc_line in result.stdout.splitlines() if proc_line.strip()]
        if not lines:
            return False

        non_menu_lines = [proc_line for proc_line in lines if "menu.elf" not in proc_line]
        return len(non_menu_lines) > 0
    except Exception as e:
        print(f"WARNING: Failed checking running elfs: {e}")
        return False


def _kill_elf_processes(reason: str) -> None:
    print(f"{reason}. Killing ELF processes...")
    try:
        # Find and kill all .elf processes
        # Using pkill -9 -f \.elf to be safer and target files with .elf extension
        subprocess.run(["pkill", "-9", "-f", r"\.elf"], check=False)
        print("Sent kill signal to .elf processes.")
    except Exception as e:
        print(f"Error killing processes: {e}")

def kill_processes(channel):
    _kill_elf_processes(f"Kill button pressed on pin {channel}")


def _note_activity(channel):
    global _last_activity
    _last_activity = _now()

def main():
    global _last_activity
    try:
        GPIO.setmode(GPIO.BCM)
        # User specified "put to a high state", so we assume Active High.
        # We set an internal Pull Down resistor so it stays Low until pressed.
        GPIO.setup(KILL_PIN, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        
        # Add event detect
        GPIO.add_event_detect(KILL_PIN, GPIO.RISING, callback=kill_processes, bouncetime=500)

        button_pins = _load_button_pins(ARCADE_CFG_PATH)
        for pin in button_pins:
            # Assumption: typical arcade wiring uses button -> GND, so treat as active-low with pull-up.
            # To be robust, we reset activity on BOTH edges.
            GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
            GPIO.add_event_detect(pin, GPIO.BOTH, callback=_note_activity, bouncetime=80)

        _last_activity = _now()

        print(f"Monitoring BCM Pin {KILL_PIN} for active HIGH kill signal...")
        print(f"Monitoring {len(button_pins)} input pins for inactivity timer...")

        while True:
            if _last_activity is not None and (_now() - _last_activity) > INACTIVITY_SECONDS:
                if _is_non_menu_elf_running():
                    _kill_elf_processes("No button activity for 5 minutes")
                _last_activity = _now()
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("Exiting monitor script.")
    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    main()
