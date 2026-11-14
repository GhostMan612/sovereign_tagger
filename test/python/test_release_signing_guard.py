"""Guardrails against silently debug-signing Android release artifacts."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
GRADLE = ROOT / "android/app/build.gradle"


class ReleaseSigningTests(unittest.TestCase):
    def test_release_build_has_no_debug_signing_fallback(self):
        gradle = GRADLE.read_text(encoding="utf-8")
        self.assertNotIn("signingConfig = signingConfigs.debug", gradle)
        self.assertIn("signingConfig = releaseSigningReady ? signingConfigs.release : null", gradle)

    def test_release_tasks_require_all_credentials(self):
        gradle = GRADLE.read_text(encoding="utf-8")
        self.assertIn("gradle.taskGraph.whenReady", gradle)
        self.assertIn("wantsRelease && !releaseSigningReady", gradle)
        self.assertIn("task.name.endsWith('Release')", gradle)
        for var in (
            "SOVEREIGN_KEYSTORE",
            "SOVEREIGN_STORE_PASSWORD",
            "SOVEREIGN_KEY_ALIAS",
            "SOVEREIGN_KEY_PASSWORD",
        ):
            self.assertIn(var, gradle)


if __name__ == "__main__":
    unittest.main()
