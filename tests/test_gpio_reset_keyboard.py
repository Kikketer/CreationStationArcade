import importlib.util
import io
import os
import struct
import sys
import types
import unittest
from unittest.mock import MagicMock, mock_open, patch

if "RPi" not in sys.modules:
    rpimod = types.ModuleType("RPi")
    gpiomod = MagicMock()
    for name in ("BCM", "IN", "PUD_UP", "PUD_DOWN", "HIGH", "LOW"):
        setattr(gpiomod, name, name)
    rpimod.GPIO = gpiomod
    sys.modules["RPi"] = rpimod
    sys.modules["RPi.GPIO"] = gpiomod

_spec = importlib.util.spec_from_file_location(
    "gpio_reset_keyboard",
    os.path.join(os.path.dirname(__file__), "..", "gpio-reset-keyboard.py"),
)
grk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(grk)


class TestGpioResetKeyboard(unittest.TestCase):
    @patch("time.sleep")
    @patch("builtins.open", new_callable=mock_open)
    @patch("fcntl.ioctl")
    def test_create_vkbd_registers_key_r(self, mock_ioctl, mock_open, _mock_sleep):
        grk.create_vkbd()
        mock_open.assert_called_once_with(grk.UINPUT_PATH, "wb+")
        calls = mock_ioctl.call_args_list
        self.assertEqual(calls[0][0][1], grk.UI_SET_EVBIT)
        self.assertEqual(calls[1][0][1], grk.UI_SET_KEYBIT)
        self.assertEqual(calls[2][0][1], grk.UI_DEV_CREATE)

    @patch("time.sleep")
    @patch("time.time", return_value=100.0)
    def test_send_r_emits_key_down_syn_up_syn(self, _mock_time, _mock_sleep):
        fd = io.BytesIO()
        grk.send_r(fd)
        fd.seek(0)
        data = fd.read()
        event_size = struct.calcsize(grk.INPUT_EVENT_FMT)
        self.assertEqual(len(data), event_size * 4)
        events = [
            struct.unpack(grk.INPUT_EVENT_FMT, data[i : i + event_size])
            for i in range(0, len(data), event_size)
        ]
        self.assertEqual(events[1][2:], (grk.EV_SYN, grk.SYN_REPORT, 0))
        self.assertEqual(events[0][2:], (grk.EV_KEY, grk.KEY_R, 1))
        self.assertEqual(events[2][2:], (grk.EV_KEY, grk.KEY_R, 0))
        self.assertEqual(events[3][2:], (grk.EV_SYN, grk.SYN_REPORT, 0))


if __name__ == "__main__":
    unittest.main()
