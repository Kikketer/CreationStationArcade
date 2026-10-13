import getpass
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class TestLaFriteNativeArcadeSetup(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.user = getpass.getuser()
        setup_path = os.path.join(
            os.path.dirname(__file__), "..", "install", "la-frite-native-arcade-setup.sh"
        )
        self.function_body = subprocess.check_output(
            ["sed", "-n", "/^inject_launcher() {/,/^}/p", setup_path],
            text=True,
        )

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run_inject(self, target, run_dir="/tmp/arcade-run", pin="20"):
        script = f"""\
ARCADE_USER='{self.user}'
ARCADE_USER_HOME='/tmp/home-test'
GPIO_RESET_PIN='{pin}'
RUN_DIR='{run_dir}'
{self.function_body}
inject_launcher '{target}'
"""
        subprocess.run(["bash", "-c", script], check=True)

    def _launcher_block(self, commented=False, pin="20"):
        prefix = "# " if commented else ""
        return (
            f"\n"
            f"# multi-native-arcade launcher\n"
            f'{prefix}if [ "$(tty)" = "/dev/tty1" ]; then\n'
            f'{prefix}  export ARCADE_LOG="$HOME/arcade.log"\n'
            f'{prefix}  export GPIO_RESET_PIN="{pin}"\n'
            f'{prefix}  cd "/tmp/arcade-run" || exit 1\n'
            f'{prefix}  exec bash "/tmp/arcade-run/launcher.sh"\n'
            f'{prefix}fi\n'
        )

    def test_fresh_file_writes_launcher_block(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertIn("multi-native-arcade launcher", content)
        self.assertIn('exec bash "/tmp/arcade-run/launcher.sh"', content)
        self.assertIn('ARCADE_LOG="$HOME/arcade.log"', content)
        self.assertNotIn("/home/pi", content)

    def test_existing_block_updates_reset_pin(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        Path(target).write_text(self._launcher_block(pin="7"))
        self._run_inject(target, pin="5")
        content = Path(target).read_text()
        self.assertIn('GPIO_RESET_PIN="5"', content)
        self.assertNotIn('GPIO_RESET_PIN="7"', content)
        self.assertEqual(content.count("multi-native-arcade launcher"), 1)

    def test_commented_block_updates_pin_without_uncommenting(self):
        target = os.path.join(self.tmpdir, "profile")
        Path(target).write_text(self._launcher_block(commented=True, pin="7"))
        self._run_inject(target, pin="5")
        content = Path(target).read_text()
        # The block should still be commented out so toggle-arcade state is preserved.
        self.assertIn('\n#   export GPIO_RESET_PIN="5"\n', content)
        self.assertNotIn('\n  export GPIO_RESET_PIN="5"\n', content)

    def test_re_running_is_stable(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject(target)
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertEqual(content.count("multi-native-arcade launcher"), 1)
        self.assertEqual(content.count("launcher.sh"), 1)

    def test_log_path_uses_home_not_pi(self):
        target = os.path.join(self.tmpdir, "profile")
        self._run_inject(target)
        content = Path(target).read_text()
        self.assertIn('ARCADE_LOG="$HOME/arcade.log"', content)
        self.assertNotIn("/home/pi", content)


if __name__ == "__main__":
    unittest.main()
