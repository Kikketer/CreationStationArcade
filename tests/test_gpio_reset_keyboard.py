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
    @patch("os.fdopen")
    @patch("os.open", return_value=99)
    @patch("fcntl.ioctl")
    def test_create_vkbd_registers_key_r(self, mock_ioctl, mock_os_open, mock_fdopen, _mock_sleep):
        grk.create_vkbd()
        mock_os_open.assert_called_once_with(grk.UINPUT_PATH, os.O_RDWR)
        mock_fdopen.assert_called_once_with(99, "wb", buffering=0)
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

    @patch.object(grk, "DISK_LOADER", "/nonexistent/arcade-disk-load.sh")
    @patch("subprocess.run")
    def test_no_disk_loader_installed_skips_sudo(self, mock_run):
        self.assertFalse(grk.try_disk_load())
        mock_run.assert_not_called()

    @patch.object(grk, "DISK_LOADER", __file__)
    @patch("subprocess.run")
    def test_disk_loader_exit_code_decides(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0)
        self.assertTrue(grk.try_disk_load())
        self.assertEqual(mock_run.call_args[0][0], ["sudo", "-n", __file__])
        mock_run.return_value = MagicMock(returncode=1)
        self.assertFalse(grk.try_disk_load())

    @patch.object(grk, "send_r")
    @patch.object(grk, "try_disk_load", return_value=False)
    def test_reset_without_new_disk_sends_r(self, _mock_load, mock_send_r):
        grk.on_reset_pressed("fd")
        mock_send_r.assert_called_once_with("fd")

    @patch.object(grk, "send_r")
    @patch.object(grk, "try_disk_load", return_value=True)
    def test_reset_with_new_disk_skips_r(self, _mock_load, mock_send_r):
        grk.on_reset_pressed("fd")
        mock_send_r.assert_not_called()


if __name__ == "__main__":
    unittest.main()
