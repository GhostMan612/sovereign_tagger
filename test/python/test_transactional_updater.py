"""Prove the transactional updater never destroys the live package first."""

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
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

    def _pending_rollback(self):
        backup = Path(str(self.live) + ".sovereign_backup")
        staging = Path(str(self.live) + ".sovereign_new")
        shutil.copytree(self.live, staging)
        (staging / "version.py").write_text(
            '__version__ = "%s"\n' % NEW_VERSION, encoding="utf-8"
        )
        os.rename(self.live, backup)
        state = {
            "phase": "backup_done",
            "target": str(self.live),
            "backup": str(backup),
            "staging": str(staging),
        }
        updater._save_state(str(self.state_dir), state)
        return backup, staging, state

    def test_transactional_update_replaces_live_package_and_cleans_up(self):
        result = self._run()
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["version"], NEW_VERSION)
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])
        self.assertIsNone(updater._load_state(str(self.state_dir)))

    def test_failed_startup_restore_preserves_backup_and_journal(self):
        backup = Path(str(self.live) + ".sovereign_backup")
        os.rename(self.live, backup)
        state = {
            "phase": "backup_done",
            "target": str(self.live),
            "backup": str(backup),
            "staging": str(self.live) + ".sovereign_new",
        }
        updater._save_state(str(self.state_dir), state)
        journal = Path(updater._state_path(str(self.state_dir)))
        original_journal = journal.read_bytes()
        original_rename = updater.os.rename

        def fail_restore(source, destination):
            if os.path.abspath(source) == str(backup):
                raise OSError("controlled backup restoration failure")
            return original_rename(source, destination)

        with patch.object(updater.os, "rename", side_effect=fail_restore):
            result = self._run()

        self.assertEqual(result["status"], "error")
        self.assertTrue(
            backup.is_dir(),
            "backup preserved=%s; journal preserved=%s"
            % (backup.is_dir(), journal.is_file()),
        )
        self.assertIn(OLD_VERSION, (backup / "version.py").read_text(encoding="utf-8"))
        self.assertEqual(journal.read_bytes(), original_journal)

    def test_repeated_failed_restore_preserves_all_recovery_evidence(self):
        backup, staging, state = self._pending_rollback()
        journal = Path(updater._state_path(str(self.state_dir)))
        original_journal = journal.read_bytes()
        original_rename = updater.os.rename

        def fail_restore(source, destination):
            if os.path.abspath(source) == str(backup):
                raise OSError("controlled backup restoration failure")
            return original_rename(source, destination)

        with patch.object(updater.os, "rename", side_effect=fail_restore):
            for _ in range(2):
                result = self._run()
                self.assertEqual(result["status"], "error")
                self.assertTrue(backup.is_dir())
                self.assertTrue(staging.is_dir())
                self.assertIn(
                    OLD_VERSION,
                    (backup / "version.py").read_text(encoding="utf-8"),
                )
                self.assertEqual(journal.read_bytes(), original_journal)
                self.assertEqual(updater._load_state(str(self.state_dir)), state)

        recovered = json.loads(updater.recover(str(self.state_dir)))
        self.assertEqual(recovered["status"], "success")
        self.assertTrue(recovered["recovered"])
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(backup.exists())
        self.assertFalse(staging.exists())
        self.assertFalse(journal.exists())

    def test_activation_and_restore_failures_preserve_backup_for_retry(self):
        backup = Path(str(self.live) + ".sovereign_backup")
        staging = Path(str(self.live) + ".sovereign_new")
        original_rename = updater.os.rename

        def fail_activation_and_restore(source, destination):
            source = os.path.abspath(source)
            if source == str(staging):
                raise OSError("controlled activation failure")
            if source == str(backup):
                raise OSError("controlled backup restoration failure")
            return original_rename(source, destination)

        with patch.object(updater.os, "rename", side_effect=fail_activation_and_restore):
            result = self._run()

        self.assertEqual(result["status"], "error")
        self.assertIn("controlled activation failure", json.dumps(result))
        self.assertIn("controlled backup restoration failure", json.dumps(result))
        self.assertFalse(self.live.exists())
        self.assertTrue(backup.is_dir())
        self.assertTrue(staging.is_dir())
        self.assertIn(OLD_VERSION, (backup / "version.py").read_text(encoding="utf-8"))
        state = updater._load_state(str(self.state_dir))
        self.assertEqual(state["phase"], "backup_done")
        self.assertEqual(state["backup"], str(backup))

        recovered = json.loads(updater.recover(str(self.state_dir)))
        self.assertEqual(recovered["status"], "success")
        self.assertTrue(recovered["recovered"])
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(backup.exists())
        self.assertFalse(staging.exists())
        self.assertIsNone(updater._load_state(str(self.state_dir)))
        retried = self._run()
        self.assertEqual(retried["status"], "success")
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])

    def test_fresh_process_recovers_preserved_failed_restore_and_can_retry(self):
        backup, staging, _ = self._pending_rollback()
        original_rename = updater.os.rename

        def fail_restore(source, destination):
            if os.path.abspath(source) == str(backup):
                raise OSError("controlled backup restoration failure")
            return original_rename(source, destination)

        with patch.object(updater.os, "rename", side_effect=fail_restore):
            failed = self._run()
        self.assertEqual(failed["status"], "error")
        self.assertTrue(backup.is_dir())
        script = (
            "import importlib.util,json,os,sys;"
            "spec=importlib.util.spec_from_file_location('fresh_updater',sys.argv[1]);"
            "module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);"
            "result=json.loads(module.recover(sys.argv[2]));"
            "result['pid']=os.getpid();print(json.dumps(result))"
        )
        process = subprocess.run(
            [sys.executable, "-X", "utf8", "-c", script, str(UPDATER_PATH), str(self.state_dir)],
            cwd=REPO,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=30,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        recovered = json.loads(process.stdout)
        self.assertNotEqual(recovered["pid"], os.getpid())
        self.assertEqual(recovered["status"], "success")
        self.assertTrue(recovered["recovered"])
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(backup.exists())
        self.assertFalse(staging.exists())
        self.assertIsNone(updater._load_state(str(self.state_dir)))
        retried = self._run()
        self.assertEqual(retried["status"], "success")
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])

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

    def test_crash_between_backup_rename_and_state_write_recovers_on_restart(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        self.assertIsNone(updater._load_state(str(self.state_dir)))

        def failing_downloader(url, dest_path):
            raise OSError("network unreachable")

        tarball = _tar_bytes(_release_files())
        with patch("urllib.request.urlopen", side_effect=_urlopen_factory(tarball)):
            result = json.loads(
                updater.execute_scorched_earth(
                    target_dir=str(self.live),
                    state_dir=str(self.state_dir),
                    downloader=failing_downloader,
                )
            )
        self.assertEqual(result["status"], "error")
        self.assertTrue(self.live.is_dir())
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))
        self.assertEqual(self._leftover_paths(), [])

    def test_backup_pending_state_is_recovered(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "backup_pending",
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

    def test_concurrent_updates_are_serialized(self):
        entries = []
        barrier = threading.Barrier(2)
        swap_lock = threading.Lock()
        original_swap = updater._swap

        def tracked_swap(target_dir, staging, state_dir):
            with swap_lock:
                entries.append(("enter", time.time()))
            try:
                return original_swap(target_dir, staging, state_dir)
            finally:
                with swap_lock:
                    entries.append(("exit", time.time()))

        tarball = _tar_bytes(_release_files())
        results = []

        def worker():
            barrier.wait()
            results.append(
                json.loads(
                    updater.execute_scorched_earth(
                        target_dir=str(self.live), state_dir=str(self.state_dir)
                    )
                )
            )

        updater._swap = tracked_swap
        try:
            with patch("urllib.request.urlopen", side_effect=_urlopen_factory(tarball)):
                threads = [threading.Thread(target=worker) for _ in range(2)]
                for thread in threads:
                    thread.start()
                for thread in threads:
                    thread.join()
        finally:
            updater._swap = original_swap

        self.assertEqual([r["status"] for r in results], ["success", "success"])
        enters = [stamp for kind, stamp in entries if kind == "enter"]
        exits = [stamp for kind, stamp in entries if kind == "exit"]
        self.assertEqual(len(enters), 2)
        self.assertGreaterEqual(enters[1], exits[0])
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])

    def test_failure_persisting_pre_rename_state_aborts_safely(self):
        calls = {"n": 0}
        original_save = updater._save_state

        def flaky_save(state_dir, state):
            calls["n"] += 1
            if calls["n"] == 2:
                raise OSError("disk full")
            return original_save(state_dir, state)

        tarball = _tar_bytes(_release_files())
        with patch("urllib.request.urlopen", side_effect=_urlopen_factory(tarball)):
            with patch.object(updater, "_save_state", side_effect=flaky_save):
                result = json.loads(
                    updater.execute_scorched_earth(
                        target_dir=str(self.live), state_dir=str(self.state_dir)
                    )
                )
        self.assertEqual(result["status"], "error")
        self.assertTrue(self.live.is_dir())
        self.assertIn(OLD_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])
        self.assertIsNone(updater._load_state(str(self.state_dir)))

    def test_crash_after_activation_before_commit_rolls_back(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        os.rename(staging, str(self.live))
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
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))
        self.assertFalse(os.path.exists(staging))

    def test_committed_state_cleanup_removes_backup_and_staging(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "committed",
                "target": str(self.live),
                "backup": backup,
                "staging": staging,
            },
        )
        result = json.loads(updater.recover(str(self.state_dir)))
        self.assertTrue(result["recovered"])
        self.assertFalse(os.path.exists(backup))
        self.assertFalse(os.path.exists(staging))
        self.assertTrue(self.live.is_dir())
        self.assertEqual(self._leftover_paths(), [])

    def test_committed_recovery_verifies_target_before_removing_backup(self):
        backup = Path(str(self.live) + ".sovereign_backup")
        shutil.copytree(self.live, backup)
        (self.live / "version.py").write_text("invalid_version = True\n", encoding="utf-8")
        state = {
            "phase": "committed", "target": str(self.live),
            "backup": str(backup), "staging": str(self.live) + ".sovereign_new",
        }
        updater._save_state(str(self.state_dir), state)
        journal = Path(updater._state_path(str(self.state_dir)))
        original_journal = journal.read_bytes()
        with self.assertRaises(updater.UpdateError):
            updater.recover(str(self.state_dir))
        self.assertIn(OLD_VERSION, (backup / "version.py").read_text(encoding="utf-8"))
        self.assertEqual(journal.read_bytes(), original_journal)

    def test_full_stack_surfaces_core_recovery_failure_without_upgrading_helpers(self):
        core = {
            "status": "error", "message": "controlled recovery failure",
            "recovery_required": True,
        }
        with patch.object(updater, "_execute_scorched_earth", return_value=json.dumps(core)):
            with patch.object(updater, "update_python_stack") as stack:
                result = json.loads(updater.execute_full_scorched_earth())
        stack.assert_not_called()
        self.assertEqual(result["message"], core["message"])
        self.assertTrue(result["recovery_required"])

    def test_repeated_recovery_is_idempotent(self):
        backup = str(self.live) + ".sovereign_backup"
        shutil.copytree(self.live, backup)
        shutil.rmtree(self.live)
        staging = str(self.live) + ".sovereign_new"
        _write_package(staging, NEW_VERSION)
        updater._save_state(
            str(self.state_dir),
            {
                "phase": "backup_pending",
                "target": str(self.live),
                "backup": backup,
                "staging": staging,
            },
        )
        first = json.loads(updater.recover(str(self.state_dir)))
        second = json.loads(updater.recover(str(self.state_dir)))
        self.assertTrue(first["recovered"])
        self.assertFalse(second["recovered"])
        self.assertTrue(self.live.is_dir())
        self.assertIn(OLD_VERSION, self._version())
        self.assertFalse(os.path.exists(backup))
        self.assertFalse(os.path.exists(staging))

    def test_unrelated_sibling_files_are_preserved(self):
        unrelated = self.live.parent / "unrelated.txt"
        unrelated.write_text("keep me", encoding="utf-8")
        result = self._run()
        self.assertEqual(result["status"], "success")
        self.assertTrue(unrelated.exists())
        self.assertEqual(unrelated.read_text(encoding="utf-8"), "keep me")
        self.assertEqual(self._leftover_paths(), [])

    def test_repeated_execution_is_idempotent(self):
        first = self._run()
        second = self._run()
        self.assertEqual(first["status"], "success", first)
        self.assertEqual(second["status"], "success", second)
        self.assertIn(NEW_VERSION, self._version())
        self.assertEqual(self._leftover_paths(), [])
        self.assertIsNone(updater._load_state(str(self.state_dir)))


if __name__ == "__main__":
    unittest.main()
