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

    def _run_inject(self, game, target, run_dir="/tmp/arcade-run", pin="13"):
        script = f"""\
ARCADE_USER='{self.user}'
ARCADE_USER_HOME='/tmp/home-test'
GAME_NAME='{game}'
GPIO_RESET_PIN='{pin}'
RUN_DIR='{run_dir}'
{self.function_body}
inject_launcher '{target}'
"""
        subprocess.run(["bash", "-c", script], check=True)

    def _launcher_block(self, game, commented=False, pin="13"):
        prefix = "# " if commented else ""
        return (
            f"\n"
            f"# single-native-arcade launcher\n"
            f'{prefix}if [ "$(tty)" = "/dev/tty1" ]; then\n'
            f'{prefix}  export ARCADE_LOG="$HOME/arcade.log"\n'
            f'{prefix}  export GPIO_RESET_PIN="{pin}"\n'
            f'{prefix}  export SINGLE_GAME_NAME="{game}"\n'
            f'{prefix}  cd "/tmp/arcade-run" || exit 1\n'
            f'{prefix}  exec bash "/tmp/arcade-run/launcher.sh"\n'
            f'{prefix}fi\n'
        )

    def test_fresh_file_writes_launcher_block(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject("PaddleTheRiver", target)
        content = Path(target).read_text()
        self.assertIn('SINGLE_GAME_NAME="PaddleTheRiver"', content)
        self.assertIn("single-native-arcade launcher", content)
        self.assertIn('exec bash "/tmp/arcade-run/launcher.sh"', content)
        self.assertIn('ARCADE_LOG="$HOME/arcade.log"', content)
        self.assertNotIn("/home/pi", content)

    def test_existing_block_updates_game_name(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        Path(target).write_text(self._launcher_block("ControllerTest"))
        self._run_inject("PaddleTheRiver", target)
        content = Path(target).read_text()
        self.assertIn('SINGLE_GAME_NAME="PaddleTheRiver"', content)
        self.assertNotIn('SINGLE_GAME_NAME="ControllerTest"', content)
        self.assertEqual(content.count("single-native-arcade launcher"), 1)

    def test_commented_block_updates_without_uncommenting(self):
        target = os.path.join(self.tmpdir, "profile")
        Path(target).write_text(self._launcher_block("ControllerTest", commented=True))
        self._run_inject("PaddleTheRiver", target)
        content = Path(target).read_text()
        self.assertIn('SINGLE_GAME_NAME="PaddleTheRiver"', content)
        self.assertNotIn('SINGLE_GAME_NAME="ControllerTest"', content)
        # The block should still be commented out so toggle-arcade state is preserved.
        self.assertIn('\n#   export SINGLE_GAME_NAME="PaddleTheRiver"\n', content)
        self.assertNotIn('\n  export SINGLE_GAME_NAME="PaddleTheRiver"\n', content)

    def test_re_running_same_game_is_stable(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        self._run_inject("PaddleTheRiver", target)
        self._run_inject("PaddleTheRiver", target)
        content = Path(target).read_text()
        self.assertEqual(content.count("single-native-arcade launcher"), 1)
        self.assertEqual(content.count('SINGLE_GAME_NAME="PaddleTheRiver"'), 1)

    def test_existing_block_updates_reset_pin(self):
        target = os.path.join(self.tmpdir, "bash_profile")
        Path(target).write_text(self._launcher_block("ControllerTest", pin="7"))
        self._run_inject("PaddleTheRiver", target, pin="5")
        content = Path(target).read_text()
        self.assertIn('GPIO_RESET_PIN="5"', content)
        self.assertNotIn('GPIO_RESET_PIN="7"', content)

    def test_log_path_uses_home_not_pi(self):
        target = os.path.join(self.tmpdir, "profile")
        self._run_inject("PaddleTheRiver", target)
        content = Path(target).read_text()
        self.assertIn('ARCADE_LOG="$HOME/arcade.log"', content)
        self.assertNotIn("/home/pi", content)


if __name__ == "__main__":
    unittest.main()
