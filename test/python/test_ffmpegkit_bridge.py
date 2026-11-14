"""Regression tests for the FFmpegKit FFI backend in the yt-dlp bridge.

`ffmpeg_kit_extended_flutter` ships `libffmpegkit.so` with a plain C API and no
Java FFmpegKit classes, so the bridge must reach it through ctypes. These tests
run off-device, where the native library is absent, and therefore pin the
failure-reporting and pass-through behaviour rather than real execution.
"""

import ctypes
import importlib.util
import json
from pathlib import Path
import sys
import types
import unittest


def _install_yt_dlp_stub():
    package = types.ModuleType("yt_dlp")
    package.__path__ = []
    utils = types.ModuleType("yt_dlp.utils")

    class Popen:
        @classmethod
        def run(cls, *args, **kwargs):
            return b"", b"", 0

    utils.Popen = Popen
    package.utils = utils
    version = types.ModuleType("yt_dlp.version")
    version.__version__ = "2026.10.26"
    package.version = version
    sys.modules["yt_dlp"] = package
    sys.modules["yt_dlp.utils"] = utils
    sys.modules["yt_dlp.version"] = version
    return package, utils


_install_yt_dlp_stub()

BRIDGE_PATH = (
    Path(__file__).resolve().parents[2]
    / "android/app/src/main/python/sovereign_yt/bridge.py"
)
spec = importlib.util.spec_from_file_location("sovereign_yt_bridge_test", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class FFmpegKitBackendTests(unittest.TestCase):
    def setUp(self):
        bridge._FFMPEGKIT.update(
            {"lib": None, "version": "", "error": "", "patched": False}
        )
        self.__original_run = bridge.yt_dlp.utils.Popen.run
        bridge._FFMPEGKIT["patched"] = False

    def tearDown(self):
        bridge.yt_dlp.utils.Popen.run = self.__original_run
        bridge._FFMPEGKIT.update(
            {"lib": None, "version": "", "error": "", "patched": False}
        )

    def _library_is_absent_on_this_host(self):
        try:
            ctypes.CDLL(bridge._FFMPEGKIT_LIB_NAMES[0])
            return False
        except OSError:
            return True

    def test_missing_library_is_reported_not_swallowed(self):
        if not self._library_is_absent_on_this_host():
            self.skipTest("libffmpegkit.so is present on this host")
        self.assertFalse(bridge._install_ffmpegkit_backend())
        report = json.loads(bridge.capabilities())
        self.assertFalse(report["ffmpegkit"])
        self.assertIn("ffmpegkit_error", report)
        self.assertTrue(report["ffmpegkit_error"])

    def test_failed_backend_is_not_cached_as_a_patch(self):
        if not self._library_is_absent_on_this_host():
            self.skipTest("libffmpegkit.so is present on this host")
        self.assertFalse(bridge._install_ffmpegkit_backend())
        self.assertFalse(bridge._FFMPEGKIT["patched"])
        # A later successful load must still be able to patch.
        bridge._FFMPEGKIT["lib"] = self._fake_lib()
        bridge._FFMPEGKIT["error"] = ""
        self.assertTrue(bridge._install_ffmpegkit_backend())
        self.assertTrue(bridge._FFMPEGKIT["patched"])

    def test_command_quoting_preserves_paths_with_spaces(self):
        command = bridge._ffmpegkit_command(
            ["ffmpeg", "-i", "/storage/My Song.m4a", "/tmp/out file.m4a"]
        )
        self.assertIn("'/storage/My Song.m4a'", command)
        self.assertIn("'/tmp/out file.m4a'", command)
        self.assertTrue(command.startswith("ffmpeg "))

    def _fake_lib(self, output=b"ffmpeg version 7.0", rc=0):
        class FakeLib:
            def ffmpeg_kit_execute(self, command):
                return 1

            def ffprobe_kit_execute(self, command):
                return 1

            def ffmpeg_kit_session_get_return_code(self, handle):
                return rc

            def ffmpeg_kit_session_get_output(self, handle):
                return output

            def ffmpeg_kit_session_get_logs_as_string(self, handle):
                return b""

            def ffmpeg_kit_config_get_ffmpeg_version(self):
                return b"7.0"

            def ffmpeg_kit_close_session(self, handle):
                return None

        return FakeLib()

    def test_non_ffmpeg_subprocesses_pass_through(self):
        bridge._FFMPEGKIT["lib"] = self._fake_lib()
        bridge._FFMPEGKIT["error"] = ""
        self.assertTrue(bridge._install_ffmpegkit_backend())
        # A non-ffmpeg command must still reach the real implementation.
        result = bridge.yt_dlp.utils.Popen.run(["python3", "-c", "pass"])
        self.assertEqual(result, (b"", b"", 0))
        # An ffmpeg command is routed to the native backend.
        stdout, stderr, rc = bridge.yt_dlp.utils.Popen.run(
            ["ffmpeg", "-i", "a.m4a", "b.m4a"]
        )
        self.assertEqual(rc, 0)
        self.assertIn(b"ffmpeg version 7.0", stdout)

    def test_patched_run_forwards_output_and_return_code(self):
        class FakeLib:
            def ffmpeg_kit_execute(self, command):
                return 1

            def ffmpeg_kit_session_get_return_code(self, handle):
                return 0

            def ffmpeg_kit_session_get_output(self, handle):
                return b"encoded output"

            def ffmpeg_kit_close_session(self, handle):
                return None

        bridge._FFMPEGKIT["lib"] = FakeLib()
        bridge._FFMPEGKIT["error"] = ""
        out, rc = bridge._ffmpegkit_exec(["ffmpeg", "-i", "in.m4a", "out.m4a"])
        self.assertEqual(out, "encoded output")
        self.assertEqual(rc, 0)

    def test_failed_session_returns_nonzero(self):
        class FakeLib:
            def ffmpeg_kit_execute(self, command):
                return 1

            def ffmpeg_kit_session_get_return_code(self, handle):
                return 1

            def ffmpeg_kit_session_get_output(self, handle):
                return b"boom"

            def ffmpeg_kit_close_session(self, handle):
                return None

        bridge._FFMPEGKIT["lib"] = FakeLib()
        out, rc = bridge._ffmpegkit_exec(["ffmpeg", "-i", "in.m4a", "out.m4a"])
        self.assertEqual(out, "boom")
        self.assertEqual(rc, 1)

    def test_null_handle_raises_instead_of_reporting_success(self):
        class FakeLib:
            def ffmpeg_kit_execute(self, command):
                return None

        bridge._FFMPEGKIT["lib"] = FakeLib()
        with self.assertRaises(OSError):
            bridge._ffmpegkit_exec(["ffmpeg", "-version"])


if __name__ == "__main__":
    unittest.main()
