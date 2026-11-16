import gzip
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPDATER = ROOT / "install" / "arcade-usb-update.sh"
DISK_LOADER = ROOT / "install" / "arcade-disk-load.sh"

# A body that passes the updater's "looks like a compiled game" check.
GAME_BODY = "// meta={}\n(function (ectx) {\nconst pxsim = ectx.pxsim;\n" + "x = 1;\n" * 4096 + "});\n"


class DiskLoadTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.games_dir = self.tmp / "arcade-games"
        self.disk = self.tmp / "disk"
        self.disk.mkdir()
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.conf = self.tmp / "arcade-usb-update.conf"
        self.conf.write_text(
            f'GAMES_DIR="{self.games_dir}"\n'
            f'ARCADE_USER="{os.environ.get("USER", "pi")}"\n'
            f'ARCADE_USER_HOME="{self.home}"\n'
            f'FLOPPY_DEV="{self.disk}"\n'
        )
        self.env = dict(
            os.environ,
            ARCADE_USB_CONF=str(self.conf),
            ARCADE_LOG=str(self.tmp / "arcade.log"),
            ARCADE_LOCK_FILE=str(self.tmp / "lock"),
            ARCADE_USB_UPDATER=str(UPDATER),
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_game_js(self, name, mtime=None, gz=False, subdir=None):
        target = self.disk / subdir if subdir else self.disk
        target.mkdir(parents=True, exist_ok=True)
        path = target / f"{name}.js{'.gz' if gz else ''}"
        data = GAME_BODY.encode()
        if gz:
            with gzip.open(path, "wb") as f:
                f.write(data)
        else:
            path.write_bytes(data)
        if mtime is not None:
            os.utime(path, (mtime, mtime))
        return path

    def run_script(self, *args):
        return subprocess.run(
            ["bash", *map(str, args)], env=self.env, capture_output=True, text=True
        )

    def active_game(self):
        return (self.games_dir / ".active-game").read_text().strip()


class TestUsbUpdateCheck(DiskLoadTestCase):
    def test_empty_disk_has_nothing_new(self):
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 1)

    def test_check_does_not_install(self):
        self.write_game_js("Floppy", mtime=1_700_000_000)
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)
        self.assertFalse((self.games_dir / "Floppy.js").exists())

    def test_installed_game_is_not_new_until_disk_changes(self):
        js = self.write_game_js("Floppy", mtime=1_700_000_000)
        self.assertEqual(self.run_script(UPDATER, self.disk).returncode, 0)
        self.assertEqual(self.active_game(), "Floppy")
        self.assertEqual(
            (self.games_dir / ".active-source-id").read_text().strip(),
            f"{js.name}:{js.stat().st_size}:1700000000",
        )
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 1)

        os.utime(js, (1_700_000_500, 1_700_000_500))
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)

    def test_other_disk_game_is_new(self):
        self.write_game_js("First", mtime=1_700_000_000)
        self.run_script(UPDATER, self.disk)
        for f in self.disk.iterdir():
            f.unlink()
        self.write_game_js("Second", mtime=1_600_000_000)
        self.assertEqual(self.run_script(UPDATER, "--check", self.disk).returncode, 0)

    def test_newest_js_wins(self):
        self.write_game_js("Old", mtime=1_600_000_000)
        self.write_game_js("New", mtime=1_700_000_000)
        self.run_script(UPDATER, self.disk)
        self.assertEqual(self.active_game(), "New")

    def test_gzipped_game_installs_decompressed(self):
        self.write_game_js("Packed", mtime=1_700_000_000, gz=True)
        self.assertEqual(self.run_script(UPDATER, self.disk).returncode, 0)
        self.assertEqual(self.active_game(), "Packed")
        installed = (self.games_dir / "Packed.js").read_text()
        self.assertIn("pxsim", installed)
        self.assertFalse((self.games_dir / "Packed.js.gz").exists())

    def test_arcade_games_folder_is_read(self):
        self.write_game_js("Folder", mtime=1_700_000_000, subdir="arcade-games")
        self.assertEqual(self.run_script(UPDATER, self.disk).returncode, 0)
        self.assertEqual(self.active_game(), "Folder")

    def test_sidecars_install_with_game(self):
        base = self.write_game_js("Floppy", mtime=1_700_000_000)
        (self.disk / "Floppy.png").write_bytes(b"png-bytes")
        (self.disk / "Floppy.json").write_text('{"name":"Floppy","author":"Kid"}')
        self.run_script(UPDATER, self.disk)
        self.assertEqual((self.games_dir / "Floppy.png").read_bytes(), b"png-bytes")
        self.assertTrue((self.games_dir / "Floppy.json").exists())

    def test_invalid_file_is_skipped(self):
        (self.disk / "NotAGame.js").write_text("<html>404</html>")
        self.assertEqual(self.run_script(UPDATER, self.disk).returncode, 0)
        self.assertFalse((self.games_dir / "NotAGame.js").exists())


class TestDiskLoad(DiskLoadTestCase):
    def test_no_drive_means_normal_reset(self):
        self.conf.write_text(
            self.conf.read_text().replace(
                f'FLOPPY_DEV="{self.disk}"', 'FLOPPY_DEV="/nonexistent/fd"'
            )
        )
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)

    def test_empty_disk_means_normal_reset(self):
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)

    def test_new_game_installs(self):
        self.write_game_js("Floppy", mtime=1_700_000_000)
        result = self.run_script(DISK_LOADER)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active_game(), "Floppy")
        self.assertTrue((self.games_dir / "Floppy.js").exists())

        # Same disk again: plain reset.
        self.assertEqual(self.run_script(DISK_LOADER).returncode, 1)

    def test_check_only_probes_without_installing(self):
        self.write_game_js("Floppy", mtime=1_700_000_000)
        self.assertEqual(self.run_script(DISK_LOADER, "--check").returncode, 0)
        self.assertFalse((self.games_dir / "Floppy.js").exists())


if __name__ == "__main__":
    unittest.main()
