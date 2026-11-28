#!/usr/bin/env python3
"""Translate calibrated cabinet inputs into standard virtual gamepads.

The service reads /etc/arcade-controller-map.json, grabs and hides those
physical input devices, then creates one Xbox-360-compatible virtual HID
gamepad per calibrated player. UHID (rather than uinput) gives every virtual
pad its own kernel HID device path, which lets Chromium expose all players as
distinct standard Gamepad API devices.
"""

import glob
import json
import os
import pwd
import selectors
import signal
import struct
import sys
import time

try:
    from evdev import InputDevice, ecodes
except ImportError as exc:
    print(f"ERROR: missing input dependency: {exc}", file=sys.stderr)
    sys.exit(2)

CONFIG = os.environ.get("ARCADE_CONTROLLER_MAP", "/etc/arcade-controller-map.json")
AXIS_THRESHOLD = 8000
MAX_PLAYERS = 4
DEVICE_NAME_PREFIX = "Creation Station Player"
RESET_KEYBOARD_NAME = "Creation Station Reset Keyboard"

ACTIONS = ("up", "down", "left", "right", "a", "b", "reset")


UHID_CREATE2 = 11
UHID_INPUT2 = 12
UHID_DESTROY = 1
BUS_USB = 0x03
XBOX360_VENDOR = 0x045E
XBOX360_PRODUCT = 0x028E

# A compact gamepad HID report descriptor. The report is 15 bytes:
#   2 bytes: 11 buttons + padding
#  12 bytes: X/Y, two triggers, and right-stick X/Y
#   1 byte: 4-bit hat switch + padding
# Matching the wired Xbox 360 layout makes Chromium expose the pads with
# Gamepad.mapping == "standard", while SDL sees ordinary joystick axes/buttons.
HID_REPORT_DESCRIPTOR = bytes([
    0x05, 0x01,                    # Usage Page (Generic Desktop)
    0x09, 0x05,                    # Usage (Game Pad)
    0xA1, 0x01,                    # Collection (Application)
    0x05, 0x09,                    # Usage Page (Button)
    0x19, 0x01,                    # Usage Minimum (Button 1)
    0x29, 0x0B,                    # Usage Maximum (Button 11)
    0x15, 0x00,                    # Logical Minimum (0)
    0x25, 0x01,                    # Logical Maximum (1)
    0x75, 0x01,                    # Report Size (1)
    0x95, 0x0B,                    # Report Count (11)
    0x81, 0x02,                    # Input (Data,Var,Abs)
    0x75, 0x01,
    0x95, 0x05,
    0x81, 0x03,                    # Input (Const,Var,Abs) padding
    0x05, 0x01,                    # Usage Page (Generic Desktop)
    0x09, 0x30,                    # X
    0x09, 0x31,                    # Y
    0x09, 0x32,                    # Z (left trigger placeholder)
    0x09, 0x33,                    # Rx
    0x09, 0x34,                    # Ry
    0x09, 0x35,                    # Rz (right trigger placeholder)
    0x16, 0x01, 0x80,              # Logical Minimum (-32767)
    0x26, 0xFF, 0x7F,              # Logical Maximum (32767)
    0x75, 0x10,
    0x95, 0x06,
    0x81, 0x02,                    # Input (Data,Var,Abs)
    0x09, 0x39,                    # Hat switch
    0x15, 0x01,
    0x25, 0x08,
    0x35, 0x00,
    0x46, 0x3B, 0x01,
    0x65, 0x14,
    0x75, 0x04,
    0x95, 0x01,
    0x81, 0x42,                    # Input (Data,Var,Abs,Null)
    0x75, 0x04,
    0x95, 0x01,
    0x81, 0x03,                    # Padding
    0xC0,                          # End Collection
])

BUTTON_BITS = {
    "a": (0,),
    "b": (1,),
    # XInput select/start become standard Gamepad buttons 8/9, which the
    # Chromium kiosk treats as exit controls. Also pulse X (raw joystick
    # button 2) because the ELF usb-to-gpio bridge uses that as its hard
    # reset control.
    # Unknown/manual configurations use the maximal legacy-compatible set.
    # Installer-written configs carry an engine field and use only the output
    # that engine understands, avoiding stray Native A/Menu presses on reset.
    "reset": (2, 6, 7),
}

RESET_BUTTON_BITS = {
    "chromium": (6, 7),
    "native": (),
    "elf": (2,),
}


def reset_button_bits(engine):
    return RESET_BUTTON_BITS.get(engine, BUTTON_BITS["reset"])

DIRECTIONS = ("up", "down", "left", "right")
TRIGGER_REST = -32767


def hat_value(directions):
    up = "up" in directions
    down = "down" in directions
    left = "left" in directions
    right = "right" in directions
    if up:
        if right:
            return 2
        if left:
            return 8
        return 1
    if down:
        if right:
            return 4
        if left:
            return 6
        return 5
    if left:
        return 7
    if right:
        return 3
    return 0


def hid_report(buttons, hat):
    axes = [0, 0, TRIGGER_REST, 0, 0, TRIGGER_REST]
    return struct.pack("<H6hB", buttons, *axes, hat)


class UhidGamepad:
    """One virtual HID gamepad backed directly by the Linux UHID API."""

    def __init__(self, name, unique_name):
        self.fd = os.open("/dev/uhid", os.O_RDWR)
        self.buttons = 0
        self.directions = set()
        self.name = name
        descriptor = HID_REPORT_DESCRIPTOR
        event = struct.pack(
            "<L128s64s64sHHLLLL4096s",
            UHID_CREATE2,
            name.encode("utf-8"),
            f"creation-station/{unique_name}".encode("utf-8"),
            unique_name.encode("utf-8"),
            len(descriptor),
            BUS_USB,
            XBOX360_VENDOR,
            XBOX360_PRODUCT,
            0,
            0,
            descriptor,
        )
        self._write(event)
        # Publish the neutral state up front so trigger axes rest at minimum
        # rather than appearing half-pressed before the first cabinet input.
        self.send_report()

    def _write(self, data):
        written = os.write(self.fd, data)
        if written != len(data):
            raise OSError(f"short UHID write: {written} != {len(data)}")

    def send_report(self):
        report = hid_report(self.buttons, hat_value(self.directions))
        event = struct.pack("<LH4096s", UHID_INPUT2, len(report), report)
        self._write(event)

    def set_action(self, action, pressed, button_bits=None):
        if action in DIRECTIONS:
            if pressed:
                self.directions.add(action)
            else:
                self.directions.discard(action)
        else:
            bits = BUTTON_BITS.get(action, ()) if button_bits is None else button_bits
            for bit in bits:
                if pressed:
                    self.buttons |= 1 << bit
                else:
                    self.buttons &= ~(1 << bit)
        self.send_report()

    def close(self):
        try:
            self._write(struct.pack("<L", UHID_DESTROY))
        except OSError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass


class ResetKeyboard:
    """Small virtual keyboard used for Native's keyboard-only reset input."""

    def __init__(self):
        from evdev import UInput

        self.device = UInput(
            {ecodes.EV_KEY: [ecodes.KEY_R]},
            name=RESET_KEYBOARD_NAME,
            vendor=XBOX360_VENDOR,
            product=XBOX360_PRODUCT,
            bustype=BUS_USB,
            phys="creation-station/reset-keyboard",
        )
        self.pressed = False

    @property
    def path(self):
        if self.device.device is None:
            return None
        return self.device.device.path

    def set_pressed(self, pressed):
        if pressed == self.pressed:
            return
        self.device.write(ecodes.EV_KEY, ecodes.KEY_R, 1 if pressed else 0)
        self.device.syn()
        self.pressed = pressed

    def close(self):
        if self.pressed:
            try:
                self.set_pressed(False)
            except OSError:
                pass
        self.device.close()


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
    """Index calibrated inputs as device -> ((kind, code, direction, threshold), player, action)."""
    by_device = {}
    for player in config.get("players", []):
        player_num = int(player.get("player", 0))
        if not 1 <= player_num <= MAX_PLAYERS:
            continue
        for action, control in player.get("controls", {}).items():
            if action not in ACTIONS:
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


def input_nodes_for_event(path):
    """Return the event node and sibling js nodes for an evdev path."""
    real_event = os.path.realpath(path)
    nodes = [real_event]
    event_name = os.path.basename(real_event)
    sysfs_device = os.path.realpath(os.path.join("/sys/class/input", event_name, "device"))
    for js in sorted(glob.glob(os.path.join(sysfs_device, "js*"))):
        nodes.append(os.path.join("/dev/input", os.path.basename(js)))
    return nodes


def hide_source_device(path, hidden_modes):
    """Make the physical input node inaccessible to non-root arcade processes.

    The service runs as root and already has the event node open, so it can
    keep reading. Hiding the event/js nodes prevents browsers and SDL from
    enumerating dormant physical controllers beside the calibrated virtual
    pads. Permissions are restored when the service stops cleanly.
    """
    for node in input_nodes_for_event(path):
        if not os.path.exists(node):
            continue
        try:
            if node not in hidden_modes:
                hidden_modes[node] = os.stat(node).st_mode & 0o777
            os.chmod(node, 0)
        except OSError:
            if node not in hidden_modes:
                hidden_modes.pop(node, None)


def restore_hidden_devices(hidden_modes):
    for node, mode in list(hidden_modes.items()):
        try:
            os.chmod(node, mode)
        except OSError:
            pass
    hidden_modes.clear()


def create_virtual_pads(config):
    outputs = {}
    for player in config.get("players", []):
        player_num = int(player.get("player", 0))
        if not 1 <= player_num <= MAX_PLAYERS or player_num in outputs or not player.get("controls"):
            continue
        outputs[player_num] = UhidGamepad(
            name=f"{DEVICE_NAME_PREFIX} {player_num}",
            unique_name=f"creation-station-player-{player_num}",
        )
    return outputs


def find_event_by_name(name):
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_path, encoding="utf-8") as f:
                if f.read().strip() == name:
                    event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
                    return os.path.join("/dev/input", event)
        except OSError:
            pass
    return None


def chown_input_nodes(nodes, owner_info):
    for node in nodes:
        try:
            stat = os.stat(node)
            if stat.st_uid != owner_info.pw_uid or stat.st_gid != owner_info.pw_gid:
                os.chown(node, owner_info.pw_uid, owner_info.pw_gid)
            if stat.st_mode & 0o777 != 0o660:
                os.chmod(node, 0o660)
        except OSError:
            pass


def set_virtual_pad_owner(outputs, owner):
    """Give the arcade user direct access to the virtual event/js nodes."""
    if not owner:
        return
    try:
        owner_info = pwd.getpwnam(owner)
    except KeyError:
        return

    for player, _device in outputs.items():
        name = f"{DEVICE_NAME_PREFIX} {player}"
        nodes = []
        for _ in range(20):
            event = find_event_by_name(name)
            nodes = input_nodes_for_event(event) if event else []
            if nodes and all(os.path.exists(node) for node in nodes):
                break
            time.sleep(0.1)
        if nodes:
            chown_input_nodes(nodes, owner_info)


def set_reset_keyboard_owner(reset_keyboard, owner):
    if reset_keyboard is None or not owner:
        return
    try:
        owner_info = pwd.getpwnam(owner)
    except KeyError:
        return
    path = reset_keyboard.path
    if path:
        chown_input_nodes(input_nodes_for_event(path), owner_info)


def config_has_reset(config):
    return any("reset" in player.get("controls", {}) for player in config.get("players", []))


def create_reset_keyboard(config):
    if not config_has_reset(config):
        return None
    engine = str(config.get("engine", "")).lower()
    if engine in ("chromium", "elf"):
        return None
    try:
        return ResetKeyboard()
    except OSError as exc:
        print(f"WARNING: cannot create reset keyboard via /dev/uinput: {exc}", file=sys.stderr)
        print("Native game reset will not work; try: sudo modprobe uinput", file=sys.stderr)
        return None


def emit_action(outputs, player, action, pressed, active, reset_keyboard=None, engine=""):
    out = outputs.get(player)
    if out is None:
        return False
    state_key = (player, action)
    if active.get(state_key) == pressed:
        return False
    try:
        if action == "reset":
            out.set_action(action, pressed, reset_button_bits(engine))
        else:
            out.set_action(action, pressed)
        if action == "reset" and reset_keyboard is not None:
            reset_keyboard.set_pressed(pressed)
    except OSError:
        return False
    active[state_key] = pressed
    return True


def release_all(outputs, active, reset_keyboard=None, engine=""):
    for player, action in list(active):
        if active.get((player, action)):
            emit_action(outputs, player, action, False, active, reset_keyboard, engine)


def main():
    config = load_config(CONFIG)
    if config is None:
        return 1
    index = build_index(config)
    if not index:
        print("ERROR: calibration file has no usable controls", file=sys.stderr)
        return 1

    try:
        outputs = create_virtual_pads(config)
    except OSError as exc:
        print(f"ERROR: cannot create virtual gamepads via /dev/uhid: {exc}", file=sys.stderr)
        print("Try: sudo modprobe uhid", file=sys.stderr)
        return 1
    if not outputs:
        print("ERROR: calibration file has no supported players", file=sys.stderr)
        return 1
    reset_keyboard = create_reset_keyboard(config)
    engine = str(config.get("engine", "")).lower()
    time.sleep(0.5)
    owner = config.get("owner", "")
    set_virtual_pad_owner(outputs, owner)
    set_reset_keyboard_owner(reset_keyboard, owner)
    last_owner_refresh = time.time()

    devices = {}
    hidden_modes = {}
    selector = selectors.DefaultSelector()
    active = {}
    axis_state = {}
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    print("Creation Station input remapper running", flush=True)
    try:
        while not stopping:
            # udev can reset virtual-device ownership shortly after creation.
            # Keep ownership aligned so the unprivileged arcade browser/SDL
            # process can open the calibrated pads.
            if time.time() - last_owner_refresh >= 2:
                set_virtual_pad_owner(outputs, owner)
                set_reset_keyboard_owner(reset_keyboard, owner)
                last_owner_refresh = time.time()

            # Open missing configured devices. This retry loop also handles
            # controllers plugged in after boot.
            for path in index:
                if path not in devices:
                    dev = open_device(path)
                    if dev:
                        devices[path] = dev
                        hide_source_device(dev.path, hidden_modes)
                        selector.register(dev, selectors.EVENT_READ, path)
                        print(f"opened {path} ({dev.name})", flush=True)

            if not devices:
                time.sleep(2)
                continue

            # Device nodes can appear slightly after the evdev node or after a
            # re-plug, so keep the hide operation idempotent.
            for dev in devices.values():
                hide_source_device(dev.path, hidden_modes)

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
                        emit_action(outputs, player, action, False, active, reset_keyboard, engine)
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
                                emit_action(outputs, player, action, True, active, reset_keyboard, engine)
                            elif event.value == 0:
                                emit_action(outputs, player, action, False, active, reset_keyboard, engine)
                        elif kind == "abs" and event.type == ecodes.EV_ABS and event.code == code:
                            pressed = (event.value * direction) >= threshold
                            state_key = (path, code, direction, player, action)
                            if axis_state.get(state_key) != pressed:
                                axis_state[state_key] = pressed
                                emit_action(outputs, player, action, pressed, active, reset_keyboard, engine)
    finally:
        release_all(outputs, active, reset_keyboard, engine)
        restore_hidden_devices(hidden_modes)
        for dev in devices.values():
            try:
                dev.close()
            except Exception:
                pass
        if reset_keyboard is not None:
            try:
                reset_keyboard.close()
            except Exception:
                pass
        for out in outputs.values():
            try:
                out.close()
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
