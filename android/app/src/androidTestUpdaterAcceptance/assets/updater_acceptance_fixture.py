# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import shutil
import tarfile
import types

OLD_VERSION = "2026.01.01"
NEW_VERSION = "2026.11.14"
_root = None
_updater = None
_last = {}
_runtime_before = None


def _safe(path):
    resolved = Path(path).resolve()
    if resolved != _root and _root not in resolved.parents:
        raise RuntimeError("Fixture path escaped the acceptance directory")
    return resolved


def _digest(path):
    digest = hashlib.sha256()
    root = _safe(path)
    for child in sorted(root.rglob("*")):
        if child.is_file():
            digest.update(child.relative_to(root).as_posix().encode("utf-8"))
            with child.open("rb") as handle:
                for chunk in iter(lambda: handle.read(65536), b""):
                    digest.update(chunk)
    return digest.hexdigest()


def _code_data(code):
    return [code.co_code.hex(), list(code.co_names), list(code.co_varnames),
            [_code_data(value) if isinstance(value, types.CodeType) else repr(value)
             for value in code.co_consts]]


def _code_digest(code):
    return hashlib.sha256(json.dumps(_code_data(code), sort_keys=True).encode("utf-8")).hexdigest()


def _runtime():
    package = importlib.import_module("yt_dlp")
    version = importlib.import_module("yt_dlp.version")
    loader = package.__spec__.loader
    return {"origin": package.__file__, "version": version.__version__,
            "code_sha256": _code_digest(loader.get_code("yt_dlp"))}


def _package(path, version):
    target = _safe(path)
    (target / "core").mkdir(parents=True, exist_ok=True)
    (target / "__init__.py").write_text("", encoding="utf-8")
    (target / "core" / "__init__.py").write_text("", encoding="utf-8")
    (target / "version.py").write_text('__version__ = "' + version + '"\n', encoding="utf-8")


def initialize(root, updater, reset):
    global _root, _updater, _runtime_before, _last
    _root = Path(root).resolve()
    _updater = updater
    if reset and _root.exists():
        shutil.rmtree(_safe(_root))
    _root.mkdir(parents=True, exist_ok=True)
    (_root / "state").mkdir(exist_ok=True)
    _runtime_before = _runtime()
    actual = Path(updater._resolve_target_dir()).resolve()
    if actual == _root or _root in actual.parents or actual in _root.parents:
        raise RuntimeError("Fixture overlaps the installed acceptance runtime")
    _last = {}
    return snapshot()


def _archive():
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w:gz") as archive:
        for name, value in {
            "__init__.py": "", "core/__init__.py": "",
            "version.py": '__version__ = "' + NEW_VERSION + '"\n',
        }.items():
            payload = value.encode("utf-8")
            entry = tarfile.TarInfo("SAMPLE_RELEASE/yt_dlp/" + name)
            entry.size = len(payload)
            archive.addfile(entry, io.BytesIO(payload))
    return data.getvalue()


def _seed_failure():
    target = _safe(_root / "yt_dlp")
    backup = _safe(str(target) + ".sovereign_backup")
    staging = _safe(str(target) + ".sovereign_new")
    for path in (target, backup, staging):
        if path.exists():
            shutil.rmtree(_safe(path))
    _package(backup, OLD_VERSION)
    _package(staging, NEW_VERSION)
    _updater._save_state(str(_root / "state"), {
        "phase": "backup_done", "target": str(target),
        "backup": str(backup), "staging": str(staging),
    })
    (_root / "checkpoint.json").write_text(json.dumps({
        "failure_pid": os.getpid(), "backup_sha256": _digest(backup),
    }), encoding="utf-8")


def run(updater, mode):
    global _last
    if updater is not _updater:
        raise RuntimeError("Unexpected updater module")
    target = _safe(_root / "yt_dlp")
    state_dir = _safe(_root / "state")
    if mode == "success":
        if target.exists():
            shutil.rmtree(_safe(target))
        _package(target, OLD_VERSION)
    elif mode == "failure":
        _seed_failure()
    elif mode != "retry":
        raise RuntimeError("Unknown isolated fixture mode")
    original_fetch = updater._fetch_release
    original_rename = updater.os.rename
    payload = _archive()

    def download(url, destination):
        if url != "fixture://SAMPLE_RELEASE":
            raise RuntimeError("Fixture attempted an uncontrolled download")
        _safe(destination).write_bytes(payload)

    def rename(source, destination):
        if mode == "failure" and Path(source) == Path(str(target) + ".sovereign_backup") and Path(destination) == target:
            raise OSError("SAMPLE FIXTURE RESTORE FAILURE")
        return original_rename(source, destination)

    try:
        updater._fetch_release = lambda: ("SAMPLE_RELEASE", "fixture://SAMPLE_RELEASE")
        updater.os.rename = rename
        raw = updater.execute_scorched_earth(str(target), str(state_dir), download)
        _last = json.loads(raw)
        return raw
    finally:
        updater._fetch_release = original_fetch
        updater.os.rename = original_rename


def snapshot():
    target = _safe(_root / "yt_dlp")
    backup = _safe(str(target) + ".sovereign_backup")
    staging = _safe(str(target) + ".sovereign_new")
    state = _updater._load_state(str(_root / "state"))
    checkpoint_path = _root / "checkpoint.json"
    checkpoint = json.loads(checkpoint_path.read_text(encoding="utf-8")) if checkpoint_path.exists() else {}
    version_path = target / "version.py"
    version = version_path.read_text(encoding="utf-8") if version_path.exists() else ""
    runtime_after = _runtime()
    return json.dumps({
        "root": str(_root), "target": str(target), "pid": os.getpid(),
        "target_exists": target.is_dir(), "target_version_source": version,
        "backup_exists": backup.is_dir(), "staging_exists": staging.is_dir(),
        "journal_exists": state is not None, "journal_phase": (state or {}).get("phase"),
        "backup_sha256": _digest(backup) if backup.is_dir() else None,
        "expected_backup_sha256": checkpoint.get("backup_sha256"),
        "failure_pid": checkpoint.get("failure_pid"), "last_response": _last,
        "runtime_import_fingerprint_unchanged": runtime_after == _runtime_before,
        "runtime": runtime_after, "updater_origin": _updater.__file__,
        "updater_code_sha256": _code_digest(_updater._execute_scorched_earth.__code__),
        "module_reload": "real updater _reload_modules executed on success",
    }, sort_keys=True)
