# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

"""Transactional, rollback-capable updater for the pinned Python stack.

The original updater deleted the live yt-dlp package before the replacement
was verified, so an interrupted download left the app unable to download
media. This replacement stages and verifies the new package beside the live
one and only then swaps them with atomic renames, keeping a durable
transaction record so an interrupted swap is rolled back (or completed) on
the next run. The live package is never removed before its replacement has
passed structural, byte-compilation and version checks.
"""

import compileall
import importlib
import importlib.metadata as importlib_metadata
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

_USER_AGENT = "SovereignTagger/1.0 (Android)"
_STATE_FILE = "sovereign_update_state.json"
_PACKAGE = "yt_dlp"
_STACK_PACKAGES = ("mutagen", "lyricsgenius")
_DOWNLOAD_TIMEOUT = 60
_CHUNK = 1 << 16
_VERSION_RE = re.compile(r'__version__\s*=\s*["\']([^"\']+)["\']')


class UpdateError(Exception):
    """Raised when an update cannot proceed without risking the live stack."""


def _updater_dir():
    return os.path.dirname(os.path.abspath(__file__))


def _state_path(state_dir):
    return os.path.join(state_dir, _STATE_FILE)


def _load_state(state_dir):
    try:
        with open(_state_path(state_dir), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _save_state(state_dir, state):
    path = _state_path(state_dir)
    part = path + ".part"
    with open(part, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(part, path)


def _remove_state(state_dir):
    for path in (_state_path(state_dir), _state_path(state_dir) + ".part"):
        try:
            os.remove(path)
        except OSError:
            pass


def _remove_artifacts(target_dir):
    """Delete every temporary sibling a transaction may have created."""
    for suffix in (
        ".sovereign_new",
        ".sovereign_extract",
        ".sovereign_download.tar.gz",
        ".sovereign_download.tar.gz.part",
        ".sovereign_backup",
    ):
        path = target_dir + suffix
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
        elif os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass


def _resolve_target_dir(explicit=None):
    if explicit:
        return os.path.abspath(explicit)
    override = os.path.join(_updater_dir(), _PACKAGE)
    try:
        import yt_dlp

        current = os.path.dirname(yt_dlp.__file__)
        if os.path.isdir(current) and ".zip" not in current:
            return os.path.abspath(current)
    except Exception:
        pass
    return override


def _recover(state, state_dir):
    """Roll back or finish a swap that a process death interrupted."""
    phase = state.get("phase")
    target = state.get("target")
    backup = state.get("backup")
    staging = state.get("staging")
    if phase == "backup_done" and backup and os.path.exists(backup):
        if target and os.path.exists(target):
            shutil.rmtree(target, ignore_errors=True)
        os.rename(backup, target)
    if phase == "committed" and backup and os.path.exists(backup):
        shutil.rmtree(backup, ignore_errors=True)
    if staging and os.path.exists(staging):
        shutil.rmtree(staging, ignore_errors=True)
    _remove_state(state_dir)
    return {"recovered_phase": phase, "target": target}


def recover(state_dir=None):
    """Public recovery entry point for a transaction left by a prior run."""
    state_dir = state_dir or _updater_dir()
    state = _load_state(state_dir)
    if not state:
        return json.dumps({"status": "success", "recovered": False})
    result = _recover(state, state_dir)
    result["status"] = "success"
    result["recovered"] = True
    return json.dumps(result)


def _download(url, dest_path):
    request = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(request, timeout=_DOWNLOAD_TIMEOUT) as response:
        with open(dest_path + ".part", "wb") as handle:
            while True:
                chunk = response.read(_CHUNK)
                if not chunk:
                    break
                handle.write(chunk)
            handle.flush()
            os.fsync(handle.fileno())
    os.replace(dest_path + ".part", dest_path)


def _fetch_release():
    request = urllib.request.Request(
        "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest",
        headers={
            "User-Agent": _USER_AGENT,
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(request, timeout=_DOWNLOAD_TIMEOUT) as response:
        payload = json.loads(response.read().decode("utf-8"))
    tag = payload.get("tag_name")
    tarball = payload.get("tarball_url")
    if not tag or not tarball:
        raise UpdateError("GitHub release payload missing tag_name/tarball_url")
    return str(tag), str(tarball)


def _extract_package(archive_path, extract_root, staging):
    if os.path.exists(extract_root):
        shutil.rmtree(extract_root)
    os.makedirs(extract_root)
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            members = archive.getmembers()
            roots = set()
            for member in members:
                name = member.name.replace("\\", "/")
                if name.startswith("/") or ".." in name.split("/"):
                    raise UpdateError("Unsafe archive member: " + member.name)
                roots.add(name.split("/")[0])
            if len(roots) != 1:
                raise UpdateError("Unexpected archive layout")
            root = roots.pop()
            prefix = root + "/" + _PACKAGE
            if not any(
                member.name.replace("\\", "/").startswith(prefix + "/")
                for member in members
            ):
                raise UpdateError("Archive does not contain " + _PACKAGE)
            try:
                archive.extractall(path=extract_root, filter="data")
            except TypeError:
                archive.extractall(path=extract_root)
    except tarfile.TarError as exc:
        raise UpdateError("Archive is not a valid tar.gz: " + str(exc))
    extracted = os.path.join(extract_root, root, _PACKAGE)
    if not os.path.isdir(extracted):
        raise UpdateError("Extracted payload missing " + _PACKAGE)
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.rename(extracted, staging)
    return staging


def _verify_package(staging):
    init = os.path.join(staging, "__init__.py")
    version_file = os.path.join(staging, "version.py")
    if not os.path.isfile(init) or not os.path.isfile(version_file):
        raise UpdateError("Staged package is missing __init__.py/version.py")
    try:
        with open(version_file, "r", encoding="utf-8") as handle:
            match = _VERSION_RE.search(handle.read())
    except OSError as exc:
        raise UpdateError("Cannot read staged version.py: " + str(exc))
    if not match:
        raise UpdateError("Staged version.py declares no __version__")
    if not compileall.compile_dir(staging, quiet=1, force=True):
        raise UpdateError("Staged package failed byte-compilation")
    return match.group(1)


def _swap(target_dir, staging, state_dir):
    backup = target_dir + ".sovereign_backup"
    if os.path.exists(backup):
        shutil.rmtree(backup)
    os.rename(target_dir, backup)
    _save_state(
        state_dir,
        {
            "phase": "backup_done",
            "target": target_dir,
            "backup": backup,
            "staging": staging,
        },
    )
    os.rename(staging, target_dir)
    _save_state(
        state_dir,
        {
            "phase": "committed",
            "target": target_dir,
            "backup": backup,
            "staging": staging,
        },
    )


def _reload_modules():
    for name in [
        key
        for key in sys.modules
        if key == _PACKAGE or key.startswith(_PACKAGE + ".")
    ]:
        del sys.modules[name]
    for name in ("sovereign_yt.bridge", "sovereign_yt.spider"):
        module = sys.modules.get(name)
        if module is not None:
            try:
                importlib.reload(module)
            except Exception:
                pass


def execute_scorched_earth(target_dir=None, state_dir=None, downloader=None):
    """Replace the live yt-dlp package with the latest release, transactionally."""
    state_dir = state_dir or _updater_dir()
    try:
        dangling = _load_state(state_dir)
        if dangling:
            _recover(dangling, state_dir)

        target = _resolve_target_dir(target_dir)
        if not os.path.isdir(target):
            raise UpdateError("Live " + _PACKAGE + " package not found at " + target)

        staging = target + ".sovereign_new"
        extract_root = target + ".sovereign_extract"
        archive = target + ".sovereign_download.tar.gz"
        _remove_artifacts(target)

        _save_state(
            state_dir, {"phase": "prepare", "target": target, "staging": staging}
        )
        tag, tarball_url = _fetch_release()
        (downloader or _download)(tarball_url, archive)
        _extract_package(archive, extract_root, staging)
        version = _verify_package(staging)
        _swap(target, staging, state_dir)
        _remove_artifacts(target)
        _remove_state(state_dir)
        _reload_modules()
        return json.dumps(
            {
                "status": "success",
                "message": "Transactional update complete: yt-dlp "
                + version
                + " (release "
                + tag
                + ").",
                "version": version,
                "tag": tag,
                "target": target,
            }
        )
    except Exception as exc:
        state = _load_state(state_dir)
        if state:
            try:
                _recover(state, state_dir)
            except Exception:
                pass
            target = state.get("target")
            if target:
                _remove_artifacts(target)
        return json.dumps({"status": "error", "message": str(exc)})


def _stack_versions():
    versions = {}
    for package in _STACK_PACKAGES:
        try:
            versions[package] = importlib_metadata.version(package)
        except Exception:
            versions[package] = None
    return versions


def _restore_stack(versions):
    restored = {}
    for package, version in versions.items():
        if not version:
            continue
        rc = subprocess.call(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--quiet",
                package + "==" + version,
            ]
        )
        restored[package] = rc == 0
    return restored


def update_python_stack():
    """Upgrade the helper packages, restoring the previous versions on failure."""
    try:
        before = _stack_versions()
        results = {}
        failed = []
        for package in _STACK_PACKAGES:
            rc = subprocess.call(
                [
                    sys.executable,
                    "-m",
                    "pip",
                    "install",
                    "--upgrade",
                    "--quiet",
                    package,
                ]
            )
            results[package] = "upgraded" if rc == 0 else "pip rc=%d" % rc
            if rc != 0:
                failed.append(package)
        if failed:
            rollback = _restore_stack({name: before.get(name) for name in failed})
            raise UpdateError(
                "pip failed for "
                + ", ".join(failed)
                + "; rollback attempted: "
                + json.dumps(rollback)
            )
        return json.dumps(
            {
                "status": "success",
                "results": results,
                "before": before,
                "after": _stack_versions(),
            }
        )
    except UpdateError as exc:
        return json.dumps({"status": "error", "message": str(exc)})
    except Exception as exc:
        return json.dumps({"status": "error", "message": str(exc)})


def execute_full_scorched_earth():
    """Update yt-dlp first, then the helper packages; never half-apply."""
    core = json.loads(execute_scorched_earth())
    if core.get("status") != "success":
        return json.dumps(
            {"status": core.get("status"), "core": core, "python_stack": None}
        )
    stack = json.loads(update_python_stack())
    status = "success" if stack.get("status") == "success" else "partial"
    return json.dumps({"status": status, "core": core, "python_stack": stack})
