# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import hashlib
import io
import json
import os
import shutil
import tarfile

from sovereign_yt import overlay_bootstrap, updater


def _add_tar_bytes(tf, arcname, raw_bytes):
    info = tarfile.TarInfo(name=arcname)
    info.size = len(raw_bytes)
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(raw_bytes))


def _build_synthetic_release_tar(version, broken_ydl=False):
    buf = io.BytesIO()
    prefix = "yt-dlp/"
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        toml = '[project]\nname = "yt-dlp"\nrequires-python = ">=3.10"\n'.encode("utf-8")
        _add_tar_bytes(tf, f"{prefix}pyproject.toml", toml)
        if broken_ydl:
            init_code = (
                "from . import version\n"
                "class YoutubeDL:\n"
                "    def __init__(self, params=None):\n"
                "        raise RuntimeError('Injected Moto G activation smoke fault')\n"
            )
        else:
            init_code = (
                "from . import version\n"
                "class YoutubeDL:\n"
                "    def __init__(self, params=None):\n"
                "        self.params = params or {}\n"
                "    def __enter__(self):\n"
                "        return self\n"
                "    def __exit__(self, *args):\n"
                "        return False\n"
            )
        ver_code = f"__version__ = {version!r}\n_channel = 'stable'\n"
        _add_tar_bytes(tf, f"{prefix}yt_dlp/__init__.py", init_code.encode("utf-8"))
        _add_tar_bytes(tf, f"{prefix}yt_dlp/version.py", ver_code.encode("utf-8"))
        _add_tar_bytes(
            tf,
            f"{prefix}yt_dlp/extractor/youtube/jsc/_builtin/vendor/yt.solver.core.js",
            b"// synthetic acceptance solver asset\n",
        )
    return buf.getvalue()


def stage_synthetic_release(overlay_root, version, bundled_version_hint, broken_ydl=False):
    tar_bytes = _build_synthetic_release_tar(version, broken_ydl=broken_ydl)
    digest = hashlib.sha256(tar_bytes).hexdigest()
    archive_url = f"https://github.com/yt-dlp/yt-dlp/releases/download/{version}/yt-dlp.tar.gz"
    sums_url = f"https://github.com/yt-dlp/yt-dlp/releases/download/{version}/SHA2-256SUMS"
    release_doc = json.dumps(
        {
            "tag_name": version,
            "draft": False,
            "prerelease": False,
            "assets": [
                {"name": "yt-dlp.tar.gz", "browser_download_url": archive_url},
                {"name": "SHA2-256SUMS", "browser_download_url": sums_url},
            ],
        }
    ).encode("utf-8")
    sums_bytes = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")

    def fetcher(url, _max_bytes):
        if url == updater.GITHUB_LATEST_RELEASE_URL:
            return release_doc
        if url == sums_url:
            return sums_bytes
        if url == archive_url:
            return tar_bytes
        raise RuntimeError(f"Unexpected acceptance fetcher URL: {url}")

    return updater.execute_scorched_earth(
        overlay_root=overlay_root,
        fetcher=fetcher,
        bundled_version_hint=bundled_version_hint,
    )


def execute_full_stack_check(overlay_root, bundled_version_hint):
    return updater.execute_full_scorched_earth(
        overlay_root=overlay_root,
        bundled_version_hint=bundled_version_hint,
    )


def inspect_live_ytdlp(overlay_root):
    import yt_dlp
    import yt_dlp.version

    runtime_state = overlay_bootstrap.get_runtime_status(overlay_root)
    mod_file = os.path.realpath(getattr(yt_dlp, "__file__", "") or "")
    slots_root = os.path.realpath(os.path.join(overlay_root, "slots"))
    return json.dumps(
        {
            "version": str(getattr(yt_dlp.version, "__version__", "") or ""),
            "file": mod_file,
            "inside_overlay_slots": overlay_bootstrap.is_path_within(slots_root, mod_file),
            "runtime_state": runtime_state,
        }
    )


def corrupt_all_overlay_slots_for_bundled_fallback(overlay_root):
    paths = overlay_bootstrap.resolve_overlay_paths(overlay_root)
    manifest, _ = overlay_bootstrap.load_manifest(paths["manifest"])
    manifest["previous_slot"] = None
    manifest["previous_version"] = None
    manifest["previous_sha256"] = None
    manifest["pending_slot"] = None
    manifest["pending_version"] = None
    manifest["pending_sha256"] = None
    active_slot = manifest.get("active_slot")
    if active_slot:
        slot_init = os.path.join(paths["slots"], active_slot, "yt_dlp", "__init__.py")
        if os.path.isfile(slot_init):
            with open(slot_init, "w", encoding="utf-8") as handle:
                handle.write("corrupt python syntax !!! (\n")
    if os.path.isdir(paths["slots"]):
        for entry in os.listdir(paths["slots"]):
            if entry != active_slot:
                shutil.rmtree(os.path.join(paths["slots"], entry), ignore_errors=True)
    overlay_bootstrap.atomic_write_json(paths["manifest"], manifest)
    return "corrupted"
