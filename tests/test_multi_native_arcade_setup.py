import getpass
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class TestMultiNativeArcadeSetup(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.user = getpass.getuser()
        setup_path = os.path.join(
            os.path.dirname(__file__), "..", "install", "multi-native-arcade-setup.sh"
        )
        self.function_body = subprocess.check_output(
            ["sed", "-n", "/^inject_launcher() {/,/^}/p", setup_path],
            text=True,
        )

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run_inject(self, target):
        script = f"""\
ARCADE_USER='{self.user}'
RUN_DIR='/tmp/arcade-run'
{self.function_body}
inject_launcher '{target}'
"""
        subprocess.run(["bash", "-c", script], check=True)

    def _launcher_block(self, commented=False):
        prefix = "# " if commented else ""
        return (
            f"\n"
            f"# multi-native-arcade launcher\n"
            f'{prefix}if [ "$(tty)" = "/dev/tty1" ]; then\n'
            f'{prefix}  cd "/tmp/arcade-run" || exit 1\n'
            f'{prefix}  exec bash "/tmp/arcade-run/launcher.sh"\n'
            f'{prefix}fi\n'
        )

    def test_fresh_file_writes_launcher_block(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertIn("multi-native-arcade launcher", content)
        self.assertIn("exec bash \"/tmp/arcade-run/launcher.sh\"", content)

    def test_existing_block_is_left_alone(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        existing = self._launcher_block()
        Path(target).write_text(existing)
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertEqual(content, existing)
        self.assertEqual(content.count("multi-native-arcade launcher"), 1)

    def test_commented_block_is_left_alone(self):
        target = os.path.join(self.tmpdir, "profile")
        existing = self._launcher_block(commented=True)
        Path(target).write_text(existing)
        self._run_inject(target)
        content = Path(target).read_text()
        # The block should still be commented out so toggle-arcade state is preserved.
        self.assertEqual(content, existing)

    def test_legacy_single_block_is_not_duplicated(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        Path(target).write_text(
            "\n# single-native-arcade launcher\n"
            'if [ "$(tty)" = "/dev/tty1" ]; then\n'
            '  cd "/tmp/arcade-run" || exit 1\n'
            '  exec bash "/tmp/arcade-run/launcher.sh"\n'
            "fi\n"
        )
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertNotIn("multi-native-arcade launcher", content)
        self.assertEqual(content.count("native-arcade launcher"), 1)

    def test_re_running_is_stable(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject(target)
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertEqual(content.count("multi-native-arcade launcher"), 1)
        self.assertEqual(content.count("launcher.sh"), 1)


if __name__ == "__main__":
    unittest.main()
