import RPi.GPIO as GPIO
import time
import subprocess
import threading
import os

ARCADE_CFG_PATH = "/home/pi/CreationStationArcade/arcade.cfg"
LOG_FILE = "/home/pi/arcade.log"

# Configuration
KILL_PIN = 3  # BCM 3
INACTIVITY_SECONDS = 2 * 60
MENU_ELF_FILE = "MadeArcadeMenu.elf"

# Determine SOURCE_DIR (same logic as launcher.sh)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.environ.get("CSA_SOURCE_DIR", f"{SCRIPT_DIR}-src")

_last_activity = None


def _log(msg: str) -> None:
    print(msg)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception:
        pass


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


PIDFILE = "/tmp/creationstation_current_elf.pid"
PXT_PID_FILE = "/tmp/pxt-pid"


def _get_game_process_name() -> str:
    """Read the PID from /tmp/pxt-pid (written by MCA ELF runtime) and return
    the process name from /proc/<pid>/comm, or empty string if not found."""
    try:
        if not os.path.exists(PXT_PID_FILE):
            return ""
        with open(PXT_PID_FILE, "r") as f:
            pid = f.readline().strip()
        if not pid:
            return ""
        comm_path = f"/proc/{pid}/comm"
        if not os.path.exists(comm_path):
            return ""
        with open(comm_path, "r") as f:
            return f.read().strip()
    except (OSError, ValueError):
        return ""


def _is_non_menu_elf_running() -> bool:
    try:
        # Primary: use /tmp/pxt-pid written by the MakeCode Arcade ELF runtime.
        # McAirpos discovered that the ELF spawns a child thread and writes its
        # PID there — this is the only reliable way to track the real game process.
        name = _get_game_process_name()
        if name and MENU_ELF_FILE[:len(name)] not in name:
            result = subprocess.run(
                ["pgrep", "-n", name],
                check=False, capture_output=True, text=True
            )
            running = result.returncode == 0
            _log(f"DEBUG _is_non_menu_elf_running: pxt-pid process '{name}' running={running}")
            return running

        _log("DEBUG _is_non_menu_elf_running: no pxt-pid or name is menu, checking /proc")
        return _scan_proc_for_elf()
    except Exception as e:
        _log(f"WARNING: Failed checking running elfs: {e}")
        return False


def _scan_proc_for_elf() -> bool:
    """Fallback: walk /proc for a non-menu .elf in any cmdline."""
    try:
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                with open(f"/proc/{entry}/cmdline", "rb") as f:
                    cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
                if ".elf" in cmdline and MENU_ELF_FILE not in cmdline:
                    _log(f"DEBUG _scan_proc_for_elf: found pid={entry} cmdline={cmdline.strip()[:80]}")
                    return True
            except (FileNotFoundError, PermissionError):
                continue
    except Exception as e:
        _log(f"WARNING: /proc scan failed: {e}")
    return False


def _update_from_git() -> None:
    """Run git fetch and reset in background (same logic as pullFromGit.sh)"""
    try:
        if not os.path.isdir(os.path.join(SOURCE_DIR, ".git")):
            print(f"Background update: source repo not found at {SOURCE_DIR}")
            return

        print(f"Background update: fetching origin from {SOURCE_DIR}")
        
        # Change to source directory and fetch
        result = subprocess.run(
            ["git", "fetch", "origin"],
            cwd=SOURCE_DIR,
            capture_output=True,
            text=True,
            timeout=15
        )
        
        if result.returncode != 0:
            print(f"Git fetch failed: {result.stderr}")
            return

        # Check if origin/main exists and if we need to reset
        check_result = subprocess.run(
            ["git", "rev-parse", "--verify", "origin/main"],
            cwd=SOURCE_DIR,
            capture_output=True,
            text=True
        )
        
        if check_result.returncode == 0:
            # Get current HEAD and origin/main
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=SOURCE_DIR,
                capture_output=True,
                text=True
            ).stdout.strip()
            
            origin_main = subprocess.run(
                ["git", "rev-parse", "origin/main"],
                cwd=SOURCE_DIR,
                capture_output=True,
                text=True
            ).stdout.strip()
            
            if head != origin_main:
                print("Background update: resetting to origin/main")
                subprocess.run(
                    ["git", "reset", "--hard", "origin/main"],
                    cwd=SOURCE_DIR,
                    capture_output=True,
                    text=True
                )
                print("Background update: reset complete")
            else:
                print("Background update: already up to date")
    except subprocess.TimeoutExpired:
        print("Git fetch timed out after 15 seconds")
    except Exception as e:
        print(f"Error during git update: {e}")


def _kill_elf_processes(reason: str) -> None:
    _log(f"{reason}. Killing ELF processes...")
    try:
        # Use the process name from /tmp/pxt-pid (written by MCA ELF runtime).
        # McAirpos uses killall <processName> — same approach here.
        name = _get_game_process_name()
        if name and MENU_ELF_FILE[:len(name)] not in name:
            subprocess.run(["killall", "-9", name], check=False)
            _log(f"Sent killall -9 {name}")
        else:
            # Fallback: pkill by .elf pattern
            subprocess.run(["pkill", "-9", "-f", r"\.elf"], check=False)
            _log("Fallback: sent pkill -9 -f .elf")
        _log("Sent kill signals to game processes.")
        
        # Start git update in background thread
        update_thread = threading.Thread(target=_update_from_git, daemon=True)
        update_thread.start()
        print("Started background git update")
        
        # Launch menu ELF file after killing processes
        menu_path = os.path.join(SCRIPT_DIR, MENU_ELF_FILE)
        if os.path.exists(menu_path) and os.access(menu_path, os.X_OK):
            print(f"Launching {menu_path} after process kill...")
            subprocess.Popen([menu_path], cwd=SCRIPT_DIR)
        else:
            print(f"WARNING: {MENU_ELF_FILE} not found or not executable at {menu_path}")
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
                    _kill_elf_processes("No button activity for 2 minutes")
                _last_activity = _now()
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("Exiting monitor script.")
    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    main()
