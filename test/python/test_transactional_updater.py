"""Prove the transactional updater never destroys the live package first."""

import importlib.util
import io
import json
import os
import shutil
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
UPDATER_PATH = REPO / "android/app/src/main/python/sovereign_yt/updater.py"

spec = importlib.util.spec_from_file_location("sovereign_yt_updater_tx", UPDATER_PATH)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)

OLD_VERSION = "2026.01.01"
NEW_VERSION = "2026.11.12"
RELEASE = {
    "tag_name": NEW_VERSION,
    "tarball_url": "https://cdn.invalid/yt-dlp.tar.gz",
}


def _write_package(root, version):
    pkg = Path(root) / "yt_dlp"
    (pkg / "core").mkdir(parents=True, exist_ok=True)
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (pkg / "version.py").write_text(
        '__version__ = "%s"\n' % version, encoding="utf-8"
    )
    (pkg / "core" / "__init__.py").write_text("", encoding="utf-8")
    return pkg


def _release_files(version=NEW_VERSION, package="yt_dlp"):
    root = "yt-dlp-%s" % version
    if package is None:
        return {root + "/README.md": "no package here"}
    return {
        root + "/" + package + "/__init__.py": "",
        root + "/" + package + "/version.py": '__version__ = "%s"\n' % version,
        root + "/" + package + "/core/__init__.py": "",
    }


def _tar_bytes(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, content in files.items():
            data = content.encode("utf-8")
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


class _FakeResponse:
    def __init__(self, data):
        self._data = data

    def read(self, size=-1):
        if size is None or size < 0:
            data, self._data = self._data, b""
            return data
        data, self._data = self._data[:size], self._data[size:]
        return data

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _urlopen_factory(tarball):
    def fake_urlopen(request, *args, **kwargs):
        url = getattr(request, "full_url", str(request))
        if "api.github.com" in url:
            return _FakeResponse(json.dumps(RELEASE).encode("utf-8"))
        return _FakeResponse(tarball)

    return fake_urlopen


class TransactionalUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="sovereign_updater_test_"))
        self.live = _write_package(self.root / "live", OLD_VERSION)
        self.state_dir = self.root / "state"
        self.state_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _version(self):
        return (self.live / "version.py").read_text(encoding="utf-8")

    def _run(self, files=None):
        tarball = _tar_bytes(files if files is not None else _release_files())
        with patch("urllib.request.urlopen", side_effect=_urlopen_factory(tarball)):
            return json.loads(
                updater.execute_scorched_earth(
                    target_dir=str(self.live), state_dir=str(self.state_dir)
                )
            )

    def _leftover_paths(self):
        return [
            path
            for path in self.root.rglob("*")
            if ".sovereign_" in path.name
        ]

    def test_transactional_update_replaces_live_package_and_cleans_up(self):
        result = self._run()
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["version"], NEW_VERSION)
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])
        self.assertIsNone(updater._load_state(str(self.state_dir)))

    def test_corrupt_archive_leaves_live_package_untouched(self):
        with patch(
            "urllib.request.urlopen",
            side_effect=_urlopen_factory(b"this is not gzip"),
        ):
            result = json.loads(
                updater.execute_scorched_earth(
                    target_dir=str(self.live), state_dir=str(self.state_dir)
                )
            )
        self.assertEqual(result["status"], "error")
        self.assertIn(OLD_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])

    def test_archive_missing_package_is_rejected(self):
        result = self._run(files=_release_files(package=None))
        self.assertEqual(result["status"], "error")
        self.assertIn(OLD_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])

    def test_path_traversal_archive_is_rejected(self):
        files = _release_files()
        files["../evil/yt_dlp/__init__.py"] = ""
        result = self._run(files=files)
        self.assertEqual(result["status"], "error")
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse((self.root / "evil").exists())

    def test_missing_live_package_fails_closed(self):
        shutil.rmtree(self.live)
        result = self._run()
        self.assertEqual(result["status"], "error")

    def test_interrupted_prepare_removes_only_staging(self):
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {"phase": "prepare", "target": str(self.live), "staging": staging},
        )
        result = json.loads(updater.recover(str(self.state_dir)))
        self.assertTrue(result["recovered"])
        self.assertTrue(self.live.is_dir())
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(os.path.exists(staging))

    def test_interrupted_swap_rolls_back_to_the_live_package(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "backup_done",
                "target": str(self.live),
                "backup": backup,
                "staging": staging,
            },
        )
        result = json.loads(updater.recover(str(self.state_dir)))
        self.assertTrue(result["recovered"])
        self.assertTrue(self.live.is_dir())
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))
        self.assertFalse(os.path.exists(staging))

    def test_committed_swap_keeps_new_package_and_drops_backup(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        _write_package(self.live.parent, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "committed",
                "target": str(self.live),
                "backup": backup,
                "staging": "",
            },
        )
        result = json.loads(updater.recover(str(self.state_dir)))
        self.assertTrue(result["recovered"])
        self.assertIn(NEW_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))

    def test_execute_recovers_a_dangling_transaction_before_updating(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "backup_done",
                "target": str(self.live),
                "backup": backup,
                "staging": "",
            },
        )
        result = self._run()
        self.assertEqual(result["status"], "success")
        self.assertIn(NEW_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))
        self.assertEqual(self._leftover_paths(), [])


if __name__ == "__main__":
    unittest.main()
