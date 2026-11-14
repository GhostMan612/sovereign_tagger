# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import hashlib
import io
import json
import os
import py_compile
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
import zipfile

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PYTHON_SRC = os.path.join(REPO_ROOT, "android", "app", "src", "main", "python")
if PYTHON_SRC not in sys.path:
    sys.path.insert(0, PYTHON_SRC)

from sovereign_yt import overlay_bootstrap, updater


def _build_synthetic_bundle_imy(dest_zip_path, version="2026.10.26", broken=False):
    os.makedirs(os.path.dirname(dest_zip_path), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        pkg_dir = os.path.join(tmp, "yt_dlp")
        os.makedirs(pkg_dir, exist_ok=True)
        init_src = (
            "from . import version\n"
            "class YoutubeDL:\n"
            "    def __init__(self, params=None):\n"
            "        if " + repr(broken) + ":\n"
            "            raise RuntimeError('broken bundled runtime')\n"
            "        self.params = params or {}\n"
            "    def __enter__(self):\n"
            "        return self\n"
            "    def __exit__(self, *args):\n"
            "        return False\n"
        )
        ver_src = f"__version__ = {version!r}\n"
        with open(os.path.join(pkg_dir, "__init__.py"), "w", encoding="utf-8") as h:
            h.write(init_src)
        with open(os.path.join(pkg_dir, "version.py"), "w", encoding="utf-8") as h:
            h.write(ver_src)
        init_pyc = os.path.join(tmp, "__init__.pyc")
        ver_pyc = os.path.join(tmp, "version.pyc")
        py_compile.compile(os.path.join(pkg_dir, "__init__.py"), cfile=init_pyc, doraise=True)
        py_compile.compile(os.path.join(pkg_dir, "version.py"), cfile=ver_pyc, doraise=True)
        with zipfile.ZipFile(dest_zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(init_pyc, "yt_dlp/__init__.pyc")
            zf.write(ver_pyc, "yt_dlp/version.pyc")
    return dest_zip_path


def _add_tar_bytes(tf, arcname, raw_bytes):
    info = tarfile.TarInfo(name=arcname)
    info.size = len(raw_bytes)
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(raw_bytes))


def _build_synthetic_tar_gz(
    version="2026.11.14",
    wrapper="yt-dlp",
    requires_python=">=3.10",
    broken_ydl=False,
    include_vendor_js=True,
    extra_entries=None,
):
    buf = io.BytesIO()
    prefix = f"{wrapper}/" if wrapper else ""
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        if requires_python:
            toml = f'[project]\nname = "yt-dlp"\nrequires-python = "{requires_python}"\n'.encode("utf-8")
            _add_tar_bytes(tf, f"{prefix}pyproject.toml", toml)

        if broken_ydl:
            init_code = (
                "from . import version\n"
                "class YoutubeDL:\n"
                "    def __init__(self, params=None):\n"
                "        raise RuntimeError('Injected smoke failure')\n"
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
        if include_vendor_js:
            _add_tar_bytes(
                tf,
                f"{prefix}yt_dlp/extractor/youtube/jsc/_builtin/vendor/yt.solver.core.js",
                b"// solver\n",
            )
        if extra_entries:
            for item in extra_entries:
                if callable(item):
                    item(tf, prefix)
                else:
                    path_rel, payload = item
                    _add_tar_bytes(tf, f"{prefix}{path_rel}", payload)
    return buf.getvalue()


def _make_release_fetcher(
    tag_name,
    archive_bytes,
    override_sha256=None,
    omit_sums=False,
    omit_archive=False,
    archive_url="https://github.com/yt-dlp/yt-dlp/releases/download/tag/yt-dlp.tar.gz",
    sums_url="https://github.com/yt-dlp/yt-dlp/releases/download/tag/SHA2-256SUMS",
    draft=False,
    prerelease=False,
):
    digest = override_sha256 or hashlib.sha256(archive_bytes).hexdigest()
    sums_text = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")
    assets = []
    if not omit_archive:
        assets.append({"name": "yt-dlp.tar.gz", "browser_download_url": archive_url})
    if not omit_sums:
        assets.append({"name": "SHA2-256SUMS", "browser_download_url": sums_url})
    release_doc = {
        "tag_name": tag_name,
        "draft": draft,
        "prerelease": prerelease,
        "assets": assets,
    }
    release_bytes = json.dumps(release_doc).encode("utf-8")

    def fetcher(url, _max_bytes):
        if url == updater.GITHUB_LATEST_RELEASE_URL:
            return release_bytes
        if url == sums_url:
            return sums_text
        if url == archive_url:
            return archive_bytes
        raise AssertionError(f"Unexpected fetch URL: {url}")

    return fetcher


def _run_isolated_child(code_snippet, bundle_imy_path, extra_sys_paths=None, env_overrides=None):
    bootstrap_paths = [PYTHON_SRC, bundle_imy_path] + list(extra_sys_paths or [])
    preamble = (
        "import sys\n"
        f"sys.path[:] = {bootstrap_paths!r} + [p for p in sys.path if p not in {bootstrap_paths!r}]\n"
    )
    env = os.environ.copy()
    env["PYTHONNOUSERSITE"] = "1"
    if env_overrides:
        env.update(env_overrides)
    proc = subprocess.run(
        [sys.executable, "-c", preamble + code_snippet],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    if proc.returncode != 0:
        raise AssertionError(f"Child failed ({proc.returncode}):\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return proc.stdout.strip()


class ChaquopyOverlayUpdaterTests(unittest.TestCase):
    def setUp(self):
        overlay_bootstrap.reset_runtime_state_for_tests()
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.overlay_root = os.path.join(self.tmp_dir.name, "sovereign_py_overlay")
        self.bundle_imy = os.path.join(self.tmp_dir.name, "requirements-arm64.imy")
        _build_synthetic_bundle_imy(self.bundle_imy, version="2026.10.26")
        self.assetfinder_ytdlp = os.path.join(self.tmp_dir.name, "AssetFinder", "requirements", "yt_dlp")
        vendor_dir = os.path.join(self.assetfinder_ytdlp, "extractor", "youtube", "jsc", "_builtin", "vendor")
        os.makedirs(vendor_dir, exist_ok=True)
        with open(os.path.join(vendor_dir, "yt.solver.core.js"), "w", encoding="utf-8") as h:
            h.write("// chaquopy vendor asset\n")

    def tearDown(self):
        overlay_bootstrap.reset_runtime_state_for_tests()
        self.tmp_dir.cleanup()

    def test_01_bundled_zipimport_bootstrap_without_overlay(self):
        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"state = overlay_bootstrap.bootstrap({self.overlay_root!r})\n"
            "import yt_dlp\n"
            "print(json.dumps({'state': state, 'file': yt_dlp.__file__, 'ver': yt_dlp.version.__version__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["state"]["active_source"], "bundled")
        self.assertEqual(out["state"]["active_version"], "2026.10.26")
        self.assertEqual(out["state"]["bundled_version"], "2026.10.26")
        self.assertFalse(out["state"]["restart_required"])
        self.assertIn("requirements-arm64.imy", out["file"])
        self.assertEqual(out["ver"], "2026.10.26")

    def test_02_data_only_assetfinder_dir_ignored(self):
        assetfinder_root = os.path.join(self.tmp_dir.name, "AssetFinder", "requirements")
        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"state = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "print(json.dumps({'state': state, 'file': yt_dlp.__file__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy, extra_sys_paths=[assetfinder_root]))
        self.assertEqual(out["state"]["active_source"], "bundled")
        self.assertNotIn("AssetFinder", out["file"])
        self.assertFalse(os.path.exists(os.path.join(self.assetfinder_ytdlp, "__init__.py")))

    def test_03_staged_update_requires_restart_and_no_in_process_hot_swap(self):
        tar_bytes = _build_synthetic_tar_gz("2026.11.14")
        digest = hashlib.sha256(tar_bytes).hexdigest()
        sums_bytes = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")
        archive_path = os.path.join(self.tmp_dir.name, "rel.tar.gz")
        with open(archive_path, "wb") as h:
            h.write(tar_bytes)
        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap, updater\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            f"archive = open({archive_path!r}, 'rb').read()\n"
            "rel = json.dumps({'tag_name': '2026.11.14', 'draft': False, 'prerelease': False, 'assets': [\n"
            "  {'name': 'yt-dlp.tar.gz', 'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.14/yt-dlp.tar.gz'},\n"
            "  {'name': 'SHA2-256SUMS', 'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.14/SHA2-256SUMS'}\n"
            "]}).encode('utf-8')\n"
            f"sums = {sums_bytes!r}\n"
            "def f(u, _): return rel if 'releases/latest' in u else (sums if 'SHA2' in u else archive)\n"
            f"res = json.loads(updater.execute_scorched_earth({self.overlay_root!r}, fetcher=f, bundled_version_hint='2026.10.26'))\n"
            "print(json.dumps({'res': res, 'live_ver': yt_dlp.version.__version__, 'live_file': yt_dlp.__file__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["res"]["status"], "success", out["res"])
        self.assertTrue(out["res"]["restart_required"])
        self.assertEqual(out["res"]["pending_version"], "2026.11.14")
        self.assertEqual(out["live_ver"], "2026.10.26")
        self.assertIn("requirements-arm64.imy", out["live_file"])

    def test_04_fresh_process_restart_activates_overlay_and_verifies_origin(self):
        tar_bytes = _build_synthetic_tar_gz("2026.11.14")
        fetcher = _make_release_fetcher("2026.11.14", tar_bytes)
        res = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(res["status"], "success")
        self.assertTrue(res["restart_required"])

        code = (
            "import json, os\n"
            "from sovereign_yt import overlay_bootstrap, updater\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "st = json.loads(updater.get_status())\n"
            "print(json.dumps({'boot': boot, 'st': st, 'file': os.path.realpath(yt_dlp.__file__), 'ver': yt_dlp.version.__version__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["boot"]["active_source"], "overlay")
        self.assertEqual(out["boot"]["active_version"], "2026.11.14")
        self.assertFalse(out["boot"]["restart_required"])
        self.assertEqual(out["ver"], "2026.11.14")
        self.assertTrue(out["file"].startswith(os.path.realpath(os.path.join(self.overlay_root, "slots"))))
        self.assertEqual(out["st"]["active_source"], "overlay")
        self.assertEqual(out["st"]["bundled_version"], "2026.10.26")

    def test_05_security_rejections(self):
        valid_tar = _build_synthetic_tar_gz("2026.11.14")

        with self.subTest("reject_http_url"):
            fetcher = _make_release_fetcher(
                "2026.11.14",
                valid_tar,
                archive_url="http://github.com/yt-dlp/yt-dlp/releases/download/tag/yt-dlp.tar.gz",
            )
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("HTTPS", res["message"])

        with self.subTest("reject_untrusted_host"):
            fetcher = _make_release_fetcher(
                "2026.11.14",
                valid_tar,
                archive_url="https://evil.example.net/yt-dlp.tar.gz",
            )
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("Untrusted", res["message"])

        with self.subTest("reject_missing_sums"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, omit_sums=True)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("SHA2-256SUMS", res["message"])

        with self.subTest("reject_bad_sha256"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, override_sha256="0" * 64)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("SHA-256", res["message"])

        with self.subTest("reject_path_traversal"):
            def add_traversal(tf, _prefix):
                _add_tar_bytes(tf, "../escape.py", b"x = 1\n")

            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[add_traversal])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_symlink"):
            def add_sym(tf, prefix):
                info = tarfile.TarInfo(name=f"{prefix}yt_dlp/link.py")
                info.type = tarfile.SYMTYPE
                info.linkname = "/etc/passwd"
                tf.addfile(info)

            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[add_sym])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("Symlink", res["message"])

        with self.subTest("reject_hardlink"):
            def add_hardlink(tf, prefix):
                info = tarfile.TarInfo(name=f"{prefix}yt_dlp/hlink.py")
                info.type = tarfile.LNKTYPE
                info.linkname = f"{prefix}yt_dlp/__init__.py"
                tf.addfile(info)

            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[add_hardlink])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("Symlink/hardlink", res["message"])

        with self.subTest("reject_zip_bomb_ratio"):
            giant = b"A" * (5 * 1024 * 1024)
            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[("yt_dlp/blob.py", giant)])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("bomb", res["message"].lower())

        with self.subTest("reject_native_elf_payload"):
            bad_tar = _build_synthetic_tar_gz(
                "2026.11.14",
                extra_entries=[("yt_dlp/native.bin", b"\x7fELF" + b"\x00" * 32)],
            )
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_tag_version_mismatch"):
            bad_tar = _build_synthetic_tar_gz("2026.11.13")
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("does not match release tag", res["message"])

        with self.subTest("reject_calver_downgrade"):
            old_tar = _build_synthetic_tar_gz("2026.01.01")
            fetcher = _make_release_fetcher("2026.01.01", old_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("downgrade", res["message"].lower())

        with self.subTest("reject_requires_python_incompatible"):
            fut_tar = _build_synthetic_tar_gz("2026.11.14", requires_python=">=9.99")
            fetcher = _make_release_fetcher("2026.11.14", fut_tar)
            res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
            self.assertEqual(res["status"], "error")
            self.assertIn("requires Python", res["message"])

    def test_06_corrupted_active_json_quarantined_and_falls_back_to_bundled(self):
        os.makedirs(self.overlay_root, exist_ok=True)
        manifest_path = os.path.join(self.overlay_root, "active.json")
        with open(manifest_path, "w", encoding="utf-8") as h:
            h.write("{corrupt json")

        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "print(json.dumps({'boot': boot, 'ver': yt_dlp.version.__version__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["boot"]["active_source"], "bundled")
        self.assertEqual(out["ver"], "2026.10.26")
        self.assertIn("Corrupted overlay manifest", out["boot"]["last_error"])
        corrupt_files = [f for f in os.listdir(self.overlay_root) if f.startswith("active.json.corrupt.")]
        self.assertTrue(corrupt_files)

    def test_07_interrupted_staging_and_interrupted_activation_recovery(self):
        stale_stage = os.path.join(self.overlay_root, "staging", "abandoned-tx")
        os.makedirs(stale_stage, exist_ok=True)
        with open(os.path.join(stale_stage, "partial.bin"), "wb") as h:
            h.write(b"half")

        tar_v1 = _build_synthetic_tar_gz("2026.11.14")
        fetcher = _make_release_fetcher("2026.11.14", tar_v1)
        res = json.loads(updater.execute_scorched_earth(self.overlay_root, fetcher=fetcher, bundled_version_hint="2026.10.26"))
        self.assertEqual(res["status"], "success")
        self.assertFalse(os.path.exists(stale_stage))

        manifest_path = os.path.join(self.overlay_root, "active.json")
        with open(manifest_path, "r", encoding="utf-8") as h:
            manifest = json.load(h)
        manifest["transaction"]["state"] = "activating"
        with open(manifest_path, "w", encoding="utf-8") as h:
            json.dump(manifest, h)

        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "print(json.dumps({'boot': boot, 'ver': yt_dlp.version.__version__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["boot"]["active_source"], "bundled")
        self.assertEqual(out["ver"], "2026.10.26")
        self.assertTrue(out["boot"]["rolled_back"])
        self.assertEqual(out["boot"]["rolled_back_from"], "2026.11.14")

    def test_08_rollback_to_previous_overlay_slot(self):
        tar_v1 = _build_synthetic_tar_gz("2026.11.01")
        res1 = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=_make_release_fetcher("2026.11.01", tar_v1),
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(res1["status"], "success")
        _run_isolated_child(
            f"from sovereign_yt import overlay_bootstrap; overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')",
            self.bundle_imy,
        )

        tar_v2_broken = _build_synthetic_tar_gz("2026.12.01", broken_ydl=True)
        res2 = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=_make_release_fetcher("2026.12.01", tar_v2_broken),
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(res2["status"], "success")

        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "print(json.dumps({'boot': boot, 'ver': yt_dlp.version.__version__, 'file': yt_dlp.__file__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["boot"]["active_source"], "overlay")
        self.assertEqual(out["boot"]["active_version"], "2026.11.01")
        self.assertEqual(out["ver"], "2026.11.01")
        self.assertTrue(out["boot"]["rolled_back"])
        self.assertEqual(out["boot"]["rolled_back_from"], "2026.12.01")

    def test_09_rollback_to_bundled_ytdlp_on_pending_smoke_failure(self):
        tar_broken = _build_synthetic_tar_gz("2026.11.14", broken_ydl=True)
        res = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=_make_release_fetcher("2026.11.14", tar_broken),
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(res["status"], "success")

        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            "print(json.dumps({'boot': boot, 'ver': yt_dlp.version.__version__, 'file': yt_dlp.__file__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertEqual(out["boot"]["active_source"], "bundled")
        self.assertEqual(out["ver"], "2026.10.26")
        self.assertIn("requirements-arm64.imy", out["file"])
        self.assertTrue(out["boot"]["rolled_back"])

    def test_10_commit_io_fault_sets_recovery_required_and_retry_succeeds(self):
        tar_v1 = _build_synthetic_tar_gz("2026.11.14")
        fetcher = _make_release_fetcher("2026.11.14", tar_v1)

        def fail_commit(_paths, _manifest, _slot_dir):
            raise OSError("Injected storage write fault")

        err = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
                commit_hook=fail_commit,
            )
        )
        self.assertEqual(err["status"], "error")
        self.assertTrue(err["recovery_required"])

        ok = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(ok["status"], "success")
        self.assertFalse(ok["recovery_required"])
        self.assertTrue(ok["restart_required"])

    def test_11_concurrent_updates_are_serialized(self):
        tar_v1 = _build_synthetic_tar_gz("2026.11.14")
        fetcher = _make_release_fetcher("2026.11.14", tar_v1)
        results = []

        def worker():
            raw = updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
            )
            results.append(json.loads(raw))

        threads = [threading.Thread(target=worker) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        self.assertEqual(len(results), 4)
        self.assertTrue(all(r["status"] == "success" for r in results))
        with open(os.path.join(self.overlay_root, "active.json"), "r", encoding="utf-8") as h:
            manifest = json.load(h)
        self.assertEqual(manifest["pending_version"], "2026.11.14")

    def test_12_repeated_update_and_restart_cycles_and_apk_supersede(self):
        for ver in ("2026.11.01", "2026.12.01", "2027.01.15"):
            tar_bytes = _build_synthetic_tar_gz(ver)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=_make_release_fetcher(ver, tar_bytes),
                    bundled_version_hint="2026.10.26",
                )
            )
            self.assertEqual(res["status"], "success")
            boot = json.loads(
                _run_isolated_child(
                    f"import json; from sovereign_yt import overlay_bootstrap; print(json.dumps(overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')))",
                    self.bundle_imy,
                )
            )
            self.assertEqual(boot["active_version"], ver)
            self.assertEqual(boot["active_source"], "overlay")

        slots = os.listdir(os.path.join(self.overlay_root, "slots"))
        self.assertLessEqual(len(slots), 2)

        newer_imy = os.path.join(self.tmp_dir.name, "requirements-newer.imy")
        _build_synthetic_bundle_imy(newer_imy, version="2027.02.01")
        boot_apk = json.loads(
            _run_isolated_child(
                f"import json; from sovereign_yt import overlay_bootstrap; print(json.dumps(overlay_bootstrap.bootstrap({self.overlay_root!r}, '2027.02.01')))",
                newer_imy,
            )
        )
        self.assertEqual(boot_apk["active_source"], "bundled")
        self.assertEqual(boot_apk["active_version"], "2027.02.01")

    def test_13_premature_ytdlp_import_detected_and_refuses_hot_swap(self):
        tar_v1 = _build_synthetic_tar_gz("2026.11.14")
        updater.execute_scorched_earth(
            self.overlay_root,
            fetcher=_make_release_fetcher("2026.11.14", tar_v1),
            bundled_version_hint="2026.10.26",
        )
        code = (
            "import json\n"
            "import yt_dlp\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "print(json.dumps({'boot': boot, 'ver': yt_dlp.version.__version__, 'file': yt_dlp.__file__}))\n"
        )
        out = json.loads(_run_isolated_child(code, self.bundle_imy))
        self.assertTrue(out["boot"]["premature_import"])
        self.assertEqual(out["boot"]["active_source"], "bundled")
        self.assertEqual(out["ver"], "2026.10.26")
        self.assertTrue(out["boot"]["restart_required"])

    def test_14_update_full_stack_returns_requires_apk_update_without_mutation(self):
        self.assertFalse(os.path.exists(self.overlay_root))
        res = json.loads(
            updater.execute_full_scorched_earth(
                self.overlay_root,
                bundled_version_hint="2026.10.26",
            )
        )
        self.assertEqual(res["status"], "requires_apk_update")
        self.assertTrue(res["core_updatable"])
        self.assertEqual(res["apk_managed_packages"], ["mutagen", "lyricsgenius"])
        self.assertFalse(os.path.exists(self.overlay_root))

    def test_15_redirect_handler_rejects_untrusted_redirect(self):
        handler = updater._TrustedRedirectHandler()
        import urllib.request
        req = urllib.request.Request("https://github.com/yt-dlp/yt-dlp/releases/latest")
        with self.assertRaises(updater.UpdaterSecurityError):
            handler.redirect_request(req, None, 302, "Found", {}, "https://untrusted.example.org/payload.tar.gz")
        with self.assertRaises(updater.UpdaterSecurityError):
            handler.redirect_request(req, None, 302, "Found", {}, "http://github.com/yt-dlp/yt-dlp/releases/latest")


if __name__ == "__main__":
    unittest.main()
