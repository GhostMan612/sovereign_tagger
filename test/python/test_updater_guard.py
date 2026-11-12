"""Prove legacy updater entry points cannot mutate a live Python environment."""

import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


UPDATER_PATH = (
    Path(__file__).resolve().parents[2]
    / "android/app/src/main/python/sovereign_yt/updater.py"
)
spec = importlib.util.spec_from_file_location("sovereign_yt_updater_guard", UPDATER_PATH)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UnsafeUpdaterGuardTests(unittest.TestCase):
    def test_all_public_updater_entry_points_fail_closed(self):
        for entry_point in (
            updater.execute_scorched_earth,
            updater.update_python_stack,
            updater.execute_full_scorched_earth,
        ):
            with self.subTest(entry_point=entry_point.__name__):
                result = json.loads(entry_point())
                self.assertEqual(result["status"], "blocked")
                self.assertEqual(result["error_code"], "UNSAFE_RUNTIME_UPDATE_DISABLED")
                self.assertIn("APK", result["message"])

    def test_disabled_updater_never_touches_network_or_disk(self):
        with (
            patch("urllib.request.urlopen", side_effect=AssertionError("network access")) as network,
            patch("shutil.rmtree", side_effect=AssertionError("delete called")) as delete,
            patch("subprocess.call", side_effect=AssertionError("pip subprocess")) as subprocess,
        ):
            updater.execute_scorched_earth()
            updater.update_python_stack()
            updater.execute_full_scorched_earth()
            network.assert_not_called()
            delete.assert_not_called()
            subprocess.assert_not_called()


if __name__ == "__main__":
    unittest.main()
