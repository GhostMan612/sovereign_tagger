"""Regression tests for the yt-dlp diagnostics adapter (stdlib only)."""

import importlib.util
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


DOCTOR_PATH = (
    Path(__file__).resolve().parents[2]
    / "android/app/src/main/python/sovereign_yt/doctor.py"
)
spec = importlib.util.spec_from_file_location("sovereign_yt_doctor_test", DOCTOR_PATH)
doctor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doctor)


class DoctorVersionTests(unittest.TestCase):
    def test_diagnose_reports_plain_version_string(self):
        package = types.ModuleType("yt_dlp")
        package.__path__ = []
        version = types.ModuleType("yt_dlp.version")
        version.__version__ = "2026.10.26"
        package.version = version

        with patch.dict(sys.modules, {"yt_dlp": package, "yt_dlp.version": version}):
            result = json.loads(doctor.diagnose())

        self.assertEqual(result["status"], "success")
        self.assertEqual(result["ytdlp_version"], "2026.10.26")

    def test_diagnose_handles_missing_yt_dlp(self):
        with patch.dict(sys.modules, {"yt_dlp": None, "yt_dlp.version": None}):
            result = json.loads(doctor.diagnose())

        self.assertEqual(result["status"], "success")
        self.assertEqual(result["ytdlp_version"], "unknown")


if __name__ == "__main__":
    unittest.main()
