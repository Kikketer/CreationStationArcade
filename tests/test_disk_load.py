import os
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPDATER = ROOT / "install" / "arcade-usb-update.sh"
DISK_LOADER = ROOT / "install" / "arcade-disk-load.sh"
# Any ELF built for this machine passes the updater's ELF + arch checks.
HOST_ELF = shutil.which("true")


class DiskLoadTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.run_dir = self.tmp / "run"
        (self.run_dir / "games" / "ControllerTest").mkdir(parents=True)
        self.disk = self.tmp / "disk"
        self.disk.mkdir()
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.conf = self.tmp / "arcade-usb-update.conf"
        self.conf.write_text(
            f'RUN_DIR="{self.run_dir}"\n'
            f'ARCADE_USER="{os.environ.get("USER", "pi")}"\n'
            f'ARCADE_USER_HOME="{self.home}"\n'
            f'FLOPPY_DEV="{self.disk}"\n'
        )
        self.pidfile = self.tmp / "game.pid"
        self.loading = self.tmp / "loading"
        self.env = dict(
            os.environ,
            ARCADE_USB_CONF=str(self.conf),
            ARCADE_LOG=str(self.tmp / "arcade.log"),
            ARCADE_LOCK_FILE=str(self.tmp / "lock"),
            ARCADE_GAME_PIDFILE=str(self.pidfile),
            ARCADE_LOADING_FILE=str(self.loading),
            ARCADE_USB_UPDATER=str(UPDATER),
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_game_tarball(self, name, mtime=None):
        src = self.tmp / f"build-{name}"
        src.mkdir(exist_ok=True)
        shutil.copy(HOST_ELF, src / "Game")
        shutil.copy(HOST_ELF, src / "libpxt.so")
        path = self.disk / f"{name}-x86-64.tar.gz"
        with tarfile.open(path, "w:gz") as tar:
            tar.add(src / "Game", "Game")
            tar.add(src / "libpxt.so", "libpxt.so")
        if mtime is not None:
            os.utime(path, (mtime, mtime))
        return path

    def run_script(self, *args):
        return subprocess.run(
            ["bash", *map(str, args)], env=self.env, capture_output=True, text=True
        )

    def active_game(self):
        return (self.run_dir / ".active-game").read_text().strip()


class TestUsbUpdateCheck(DiskLoadTestCase):
    def test_empty_disk_has_nothing_new(self):
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 1)

    def test_check_does_not_install(self):
        self.write_game_tarball("Floppy", mtime=1_700_000_000)
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)
        self.assertFalse((self.run_dir / "games" / "Floppy").exists())

    def test_installed_game_is_not_new_until_disk_changes(self):
        tar = self.write_game_tarball("Floppy", mtime=1_700_000_000)
        self.assertEqual(self.run_script(UPDATER, self.disk).returncode, 0)
        self.assertEqual(self.active_game(), "Floppy")
        self.assertEqual(
            (self.run_dir / "games" / "Floppy" / ".usb-source-id").read_text().strip(),
            f"{tar.name}:{tar.stat().st_size}:1700000000",
        )
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 1)

        os.utime(tar, (1_700_000_500, 1_700_000_500))
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)

    def test_other_disk_game_is_new(self):
        self.write_game_tarball("First", mtime=1_700_000_000)
        self.run_script(UPDATER, self.disk)
        for f in self.disk.iterdir():
            f.unlink()
        self.write_game_tarball("Second", mtime=1_600_000_000)
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)


class TestDiskLoad(DiskLoadTestCase):
    def test_no_drive_means_normal_reset(self):
        self.conf.write_text(self.conf.read_text().replace(f'FLOPPY_DEV="{self.disk}"', 'FLOPPY_DEV="/nonexistent/fd"'))
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)

    def test_empty_disk_means_normal_reset(self):
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)

    def test_new_game_stops_running_game_and_installs(self):
        self.write_game_tarball("Floppy", mtime=1_700_000_000)
        game = subprocess.Popen(["sleep", "60"])
        try:
            self.pidfile.write_text(str(game.pid))
            result = self.run_script(DISK_LOADER)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for _ in range(50):
                if game.poll() is not None:
                    break
                time.sleep(0.1)
            self.assertIsNotNone(game.poll(), "running Game was not stopped")
        finally:
            game.kill()
            game.wait()
        self.assertEqual(self.active_game(), "Floppy")
        self.assertTrue((self.run_dir / "games" / "Floppy" / "Game").exists())
        self.assertFalse(self.loading.exists())

        # Same disk again: plain reset.
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)


if __name__ == "__main__":
    unittest.main()
