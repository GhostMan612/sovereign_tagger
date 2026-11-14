# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import base64
import hashlib
import io
import json
import os
import py_compile
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
import zipfile

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PYTHON_SRC = os.path.join(REPO_ROOT, "android", "app", "src", "main", "python")
if PYTHON_SRC not in sys.path:
    sys.path.insert(0, PYTHON_SRC)

from sovereign_yt import overlay_bootstrap, updater


def _is_probable_prime(n):
    if n < 2:
        return False
    for small in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n == small:
            return True
        if n % small == 0:
            return False
    d = n - 1
    s = 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for a in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53):
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(s - 1):
            x = (x * x) % n
            if x == n - 1:
                break
        else:
            return False
    return True


def _encode_mpi(val):
    bits = val.bit_length()
    raw = val.to_bytes((bits + 7) // 8, "big")
    return struct.pack(">H", bits) + raw


def _make_test_rsa_key(seed_tag=1, label="test-release-rsa"):
    e = 65537
    p = ((1 << 512) + 0x10001 * seed_tag) | 1
    while not (_is_probable_prime(p) and (p - 1) % e != 0):
        p += 2
    q = ((1 << 512) + 0x20003 * seed_tag + 0x9999) | 1
    while not (q != p and _is_probable_prime(q) and (q - 1) % e != 0):
        q += 2
    n = p * q
    phi = (p - 1) * (q - 1)
    d = pow(e, -1, phi)
    pub_body = b"\x04" + struct.pack(">I", 1700000000 + seed_tag) + b"\x01" + _encode_mpi(n) + _encode_mpi(e)
    fpr_bytes = hashlib.sha1(b"\x99" + struct.pack(">H", len(pub_body)) + pub_body).digest()
    return {
        "label": label,
        "fingerprint": fpr_bytes.hex().upper(),
        "key_id": fpr_bytes[-8:].hex().upper(),
        "e": e,
        "n": n,
        "d": d,
    }


def _public_key_entry(full_key):
    return {k: full_key[k] for k in ("label", "fingerprint", "key_id", "e", "n")}


def _subpkt(sub_type, val, critical=False):
    raw_type = sub_type | (0x80 if critical else 0)
    return bytes([1 + len(val), raw_type]) + val


def _sign_openpgp_v4_rsa(
    data_bytes,
    full_key,
    hash_algo=10,
    sigtype=0x00,
    include_fpr=True,
    include_kid=True,
    armor=False,
    bad_crc=False,
    critical_unknown=False,
    unhashed_kid_only=False,
):
    hashed_parts = [_subpkt(2, struct.pack(">I", 1730000000))]
    if include_fpr and not unhashed_kid_only:
        hashed_parts.append(_subpkt(33, b"\x04" + bytes.fromhex(full_key["fingerprint"])))
    if include_kid and not unhashed_kid_only:
        hashed_parts.append(_subpkt(16, bytes.fromhex(full_key["key_id"])))
    if critical_unknown:
        hashed_parts.append(_subpkt(99, b"\x01\x02", critical=True))
    hashed_blob = b"".join(hashed_parts)
    unhashed_blob = _subpkt(16, bytes.fromhex(full_key["key_id"])) if unhashed_kid_only else b""

    header = bytes([4, sigtype, 1, hash_algo]) + struct.pack(">H", len(hashed_blob)) + hashed_blob
    msg = data_bytes
    if sigtype == 0x01:
        msg = b"\r\n".join(data_bytes.replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n"))

    hash_fn, der_prefix = updater._PGP_DIGEST_INFOS[hash_algo]
    hasher = hash_fn()
    hasher.update(msg)
    hasher.update(header)
    hasher.update(b"\x04\xff" + struct.pack(">I", len(header)))
    digest = hasher.digest()

    k_bytes = (full_key["n"].bit_length() + 7) // 8
    t_bytes = der_prefix + digest
    em = b"\x00\x01" + (b"\xff" * (k_bytes - len(t_bytes) - 3)) + b"\x00" + t_bytes
    sig_int = pow(int.from_bytes(em, "big"), full_key["d"], full_key["n"])
    body = header + struct.pack(">H", len(unhashed_blob)) + unhashed_blob + digest[:2] + _encode_mpi(sig_int)

    pkt_len = len(body)
    if pkt_len < 192:
        len_hdr = bytes([pkt_len])
    elif pkt_len < 8384:
        adj = pkt_len - 192
        len_hdr = bytes([192 + (adj >> 8), adj & 0xFF])
    else:
        len_hdr = b"\xff" + struct.pack(">I", pkt_len)
    pkt = b"\xc2" + len_hdr + body

    if armor:
        b64 = base64.b64encode(pkt).decode("ascii")
        lines = [b64[i : i + 64] for i in range(0, len(b64), 64)]
        crc = updater._crc24_openpgp(pkt) ^ (1 if bad_crc else 0)
        crc_b64 = base64.b64encode(crc.to_bytes(3, "big")).decode("ascii")
        armored = (
            "-----BEGIN PGP SIGNATURE-----\n\n"
            + "\n".join(lines)
            + f"\n={crc_b64}\n-----END PGP SIGNATURE-----\n"
        )
        return armored.encode("ascii")
    return pkt


_TEST_PGP_KEY = _make_test_rsa_key(seed_tag=1, label="test-release-rsa")
_OTHER_PGP_KEY = _make_test_rsa_key(seed_tag=2, label="other-release-rsa")
_TEST_PINNED_KEYS = (_public_key_entry(_TEST_PGP_KEY),)


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
    omit_sig=False,
    omit_archive=False,
    archive_url="https://github.com/yt-dlp/yt-dlp/releases/download/tag/yt-dlp.tar.gz",
    sums_url="https://github.com/yt-dlp/yt-dlp/releases/download/tag/SHA2-256SUMS",
    sig_url="https://github.com/yt-dlp/yt-dlp/releases/download/tag/SHA2-256SUMS.sig",
    draft=False,
    prerelease=False,
    signing_key=None,
    override_sums_bytes=None,
    override_sig_bytes=None,
    hash_algo=10,
    sigtype=0x00,
    armor=False,
    bad_crc=False,
    critical_unknown=False,
    unhashed_kid_only=False,
):
    digest = override_sha256 or hashlib.sha256(archive_bytes).hexdigest()
    default_sums = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")
    sums_text = override_sums_bytes if override_sums_bytes is not None else default_sums
    active_key = signing_key or _TEST_PGP_KEY
    sig_bytes = (
        override_sig_bytes
        if override_sig_bytes is not None
        else _sign_openpgp_v4_rsa(
            default_sums,
            active_key,
            hash_algo=hash_algo,
            sigtype=sigtype,
            armor=armor,
            bad_crc=bad_crc,
            critical_unknown=critical_unknown,
            unhashed_kid_only=unhashed_kid_only,
        )
    )
    assets = []
    if not omit_archive:
        assets.append({"name": "yt-dlp.tar.gz", "browser_download_url": archive_url})
    if not omit_sums:
        assets.append({"name": "SHA2-256SUMS", "browser_download_url": sums_url})
    if not omit_sig:
        assets.append({"name": "SHA2-256SUMS.sig", "browser_download_url": sig_url})
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
        if url == sig_url:
            return sig_bytes
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
        sig_bytes = _sign_openpgp_v4_rsa(sums_bytes, _TEST_PGP_KEY)
        archive_path = os.path.join(self.tmp_dir.name, "rel.tar.gz")
        with open(archive_path, "wb") as h:
            h.write(tar_bytes)
        pinned = list(_TEST_PINNED_KEYS)
        code = (
            "import json\n"
            "from sovereign_yt import overlay_bootstrap, updater\n"
            f"boot = overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')\n"
            "import yt_dlp\n"
            f"archive = open({archive_path!r}, 'rb').read()\n"
            "rel = json.dumps({'tag_name': '2026.11.14', 'draft': False, 'prerelease': False, 'assets': [\n"
            "  {'name': 'yt-dlp.tar.gz', 'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.14/yt-dlp.tar.gz'},\n"
            "  {'name': 'SHA2-256SUMS', 'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.14/SHA2-256SUMS'},\n"
            "  {'name': 'SHA2-256SUMS.sig', 'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.14/SHA2-256SUMS.sig'}\n"
            "]}).encode('utf-8')\n"
            f"sums = {sums_bytes!r}\n"
            f"sig = {sig_bytes!r}\n"
            f"pins = {pinned!r}\n"
            "def f(u, _):\n"
            "    if 'releases/latest' in u: return rel\n"
            "    if u.endswith('.sig'): return sig\n"
            "    if 'SHA2' in u: return sums\n"
            "    return archive\n"
            f"res = json.loads(updater.execute_scorched_earth({self.overlay_root!r}, fetcher=f, bundled_version_hint='2026.10.26', pinned_keys=pins))\n"
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
                pinned_keys=_TEST_PINNED_KEYS,
            )
        )
        self.assertEqual(res["status"], "success", res)
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
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("HTTPS", res["message"])

        with self.subTest("reject_untrusted_host"):
            fetcher = _make_release_fetcher(
                "2026.11.14",
                valid_tar,
                archive_url="https://evil.example.net/yt-dlp.tar.gz",
            )
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("Untrusted", res["message"])

        with self.subTest("reject_missing_sums"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, omit_sums=True)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("SHA2-256SUMS", res["message"])

        with self.subTest("reject_bad_sha256"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, override_sha256="0" * 64)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("SHA-256", res["message"])

        with self.subTest("reject_path_traversal"):
            def add_traversal(tf, _prefix):
                _add_tar_bytes(tf, "../escape.py", b"x = 1\n")

            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[add_traversal])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_symlink"):
            def add_sym(tf, prefix):
                info = tarfile.TarInfo(name=f"{prefix}yt_dlp/link.py")
                info.type = tarfile.SYMTYPE
                info.linkname = "/etc/passwd"
                tf.addfile(info)

            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[add_sym])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
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
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("Symlink/hardlink", res["message"])

        with self.subTest("reject_zip_bomb_ratio"):
            giant = b"A" * (5 * 1024 * 1024)
            bad_tar = _build_synthetic_tar_gz("2026.11.14", extra_entries=[("yt_dlp/blob.py", giant)])
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("bomb", res["message"].lower())

        with self.subTest("reject_native_elf_payload"):
            bad_tar = _build_synthetic_tar_gz(
                "2026.11.14",
                extra_entries=[("yt_dlp/native.bin", b"\x7fELF" + b"\x00" * 32)],
            )
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_tag_version_mismatch"):
            bad_tar = _build_synthetic_tar_gz("2026.11.13")
            fetcher = _make_release_fetcher("2026.11.14", bad_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("does not match release tag", res["message"])

        with self.subTest("reject_calver_downgrade"):
            old_tar = _build_synthetic_tar_gz("2026.01.01")
            fetcher = _make_release_fetcher("2026.01.01", old_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("downgrade", res["message"].lower())

        with self.subTest("reject_requires_python_incompatible"):
            fut_tar = _build_synthetic_tar_gz("2026.11.14", requires_python=">=9.99")
            fetcher = _make_release_fetcher("2026.11.14", fut_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
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
        res = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
                pinned_keys=_TEST_PINNED_KEYS,
            )
        )
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
                pinned_keys=_TEST_PINNED_KEYS,
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
                pinned_keys=_TEST_PINNED_KEYS,
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
                pinned_keys=_TEST_PINNED_KEYS,
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
                pinned_keys=_TEST_PINNED_KEYS,
            )
        )
        self.assertEqual(err["status"], "error")
        self.assertTrue(err["recovery_required"])

        ok = json.loads(
            updater.execute_scorched_earth(
                self.overlay_root,
                fetcher=fetcher,
                bundled_version_hint="2026.10.26",
                pinned_keys=_TEST_PINNED_KEYS,
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
                pinned_keys=_TEST_PINNED_KEYS,
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
                    pinned_keys=_TEST_PINNED_KEYS,
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
            pinned_keys=_TEST_PINNED_KEYS,
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

    def test_16_openpgp_signature_security_and_variants(self):
        valid_tar = _build_synthetic_tar_gz("2026.11.14")
        digest = hashlib.sha256(valid_tar).hexdigest()
        sums_lf = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")
        sums_crlf = f"{digest}  yt-dlp.tar.gz\r\n".encode("utf-8")

        with self.subTest("reject_missing_sig_asset"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, omit_sig=True)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("SHA2-256SUMS.sig", res["message"])

        with self.subTest("reject_synthetic_key_under_production_pin"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("issuer", res["message"].lower())

        with self.subTest("reject_wrong_signing_key"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, signing_key=_OTHER_PGP_KEY)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_tampered_sums_against_valid_sig"):
            tampered_sums = sums_lf.replace(b"yt-dlp.tar.gz", b"yt-evil.tar.gz")
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, override_sums_bytes=tampered_sums)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_bit_flipped_sig"):
            raw_sig = bytearray(_sign_openpgp_v4_rsa(sums_lf, _TEST_PGP_KEY))
            raw_sig[-10] ^= 0x55
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, override_sig_bytes=bytes(raw_sig))
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")

        with self.subTest("reject_unknown_critical_subpacket"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, critical_unknown=True)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("critical", res["message"].lower())

        with self.subTest("reject_armored_bad_crc24"):
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, armor=True, bad_crc=True)
            res = json.loads(
                updater.execute_scorched_earth(
                    self.overlay_root,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "error")
            self.assertIn("CRC24", res["message"])

        with self.subTest("accept_sha256_armored_canonical_text_and_kid_fallback"):
            matched_sha256 = updater.verify_openpgp_rsa_detached(
                sums_lf,
                _sign_openpgp_v4_rsa(sums_lf, _TEST_PGP_KEY, hash_algo=8),
                pinned_keys=_TEST_PINNED_KEYS,
            )
            self.assertEqual(matched_sha256["fingerprint"], _TEST_PGP_KEY["fingerprint"])

            matched_text = updater.verify_openpgp_rsa_detached(
                sums_lf,
                _sign_openpgp_v4_rsa(sums_crlf, _TEST_PGP_KEY, sigtype=0x01),
                pinned_keys=_TEST_PINNED_KEYS,
            )
            self.assertEqual(matched_text["fingerprint"], _TEST_PGP_KEY["fingerprint"])

            matched_kid = updater.verify_openpgp_rsa_detached(
                sums_lf,
                _sign_openpgp_v4_rsa(sums_lf, _TEST_PGP_KEY, unhashed_kid_only=True),
                pinned_keys=_TEST_PINNED_KEYS,
            )
            self.assertEqual(matched_kid["key_id"], _TEST_PGP_KEY["key_id"])

            ok_dir = os.path.join(self.tmp_dir.name, "overlay_armored")
            fetcher = _make_release_fetcher("2026.11.14", valid_tar, hash_algo=8, armor=True)
            res = json.loads(
                updater.execute_scorched_earth(
                    ok_dir,
                    fetcher=fetcher,
                    bundled_version_hint="2026.10.26",
                    pinned_keys=_TEST_PINNED_KEYS,
                )
            )
            self.assertEqual(res["status"], "success", res)
            self.assertTrue(res["restart_required"])

    def test_17_cross_process_overlay_lock_and_readonly_no_mkdir(self):
        missing_root = os.path.join(self.tmp_dir.name, "never_created_overlay")
        st = overlay_bootstrap.get_runtime_status(missing_root)
        self.assertFalse(st["initialized"])
        self.assertFalse(os.path.exists(missing_root))

        status_res = json.loads(updater.get_status(missing_root, bundled_version_hint="2026.10.26"))
        self.assertEqual(status_res["status"], "success")
        self.assertFalse(os.path.exists(missing_root))

        with overlay_bootstrap.overlay_file_lock(self.overlay_root, create=True):
            self.assertEqual(overlay_bootstrap._FILE_LOCK_DEPTH, 1)
            with overlay_bootstrap.overlay_file_lock(self.overlay_root, create=True):
                self.assertEqual(overlay_bootstrap._FILE_LOCK_DEPTH, 2)
            self.assertEqual(overlay_bootstrap._FILE_LOCK_DEPTH, 1)
        self.assertEqual(overlay_bootstrap._FILE_LOCK_DEPTH, 0)

        child_code = (
            "import sys, time\n"
            f"sys.path.insert(0, {PYTHON_SRC!r})\n"
            "from sovereign_yt import overlay_bootstrap\n"
            f"with overlay_bootstrap.overlay_file_lock({self.overlay_root!r}, create=True):\n"
            "    sys.stdout.write('LOCKED\\n')\n"
            "    sys.stdout.flush()\n"
            "    time.sleep(0.55)\n"
        )
        proc = subprocess.Popen(
            [sys.executable, "-c", child_code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            ready_line = proc.stdout.readline().strip()
            self.assertEqual(ready_line, "LOCKED")
            t0 = time.monotonic()
            with overlay_bootstrap.overlay_file_lock(self.overlay_root, create=True):
                elapsed = time.monotonic() - t0
            self.assertGreaterEqual(elapsed, 0.35)
        finally:
            _, stderr = proc.communicate(timeout=15)
        self.assertEqual(proc.returncode, 0, stderr)

    def test_18_quarantine_manifest_cap_and_bootstrap_staging_prune(self):
        os.makedirs(self.overlay_root, exist_ok=True)
        manifest_path = os.path.join(self.overlay_root, "active.json")
        for _ in range(5):
            with open(manifest_path, "w", encoding="utf-8") as h:
                h.write("{corrupt")
            time.sleep(0.02)
            code = (
                "import json\n"
                "from sovereign_yt import overlay_bootstrap\n"
                f"print(json.dumps(overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')))\n"
            )
            boot = json.loads(_run_isolated_child(code, self.bundle_imy))
            self.assertEqual(boot["active_source"], "bundled")

        corrupt_files = [f for f in os.listdir(self.overlay_root) if f.startswith("active.json.corrupt.")]
        self.assertLessEqual(len(corrupt_files), overlay_bootstrap._MAX_QUARANTINED_MANIFESTS)
        self.assertGreaterEqual(len(corrupt_files), 1)

        orphan_stage = os.path.join(self.overlay_root, "staging", "orphan-tx")
        os.makedirs(orphan_stage, exist_ok=True)
        with open(os.path.join(orphan_stage, "leftover.bin"), "wb") as h:
            h.write(b"stale")

        _run_isolated_child(
            f"from sovereign_yt import overlay_bootstrap; overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')",
            self.bundle_imy,
        )
        self.assertFalse(os.path.exists(orphan_stage))

        recovery_manifest = overlay_bootstrap.default_manifest("2026.10.26")
        recovery_manifest["recovery_required"] = True
        recovery_manifest["transaction"]["state"] = "recovery_required"
        overlay_bootstrap.atomic_write_json(manifest_path, recovery_manifest)

        recovery_stage = os.path.join(self.overlay_root, "staging", "recovery-evidence")
        os.makedirs(recovery_stage, exist_ok=True)
        with open(os.path.join(recovery_stage, "part.bin"), "wb") as h:
            h.write(b"keep")

        _run_isolated_child(
            f"from sovereign_yt import overlay_bootstrap; overlay_bootstrap.bootstrap({self.overlay_root!r}, '2026.10.26')",
            self.bundle_imy,
        )
        self.assertTrue(os.path.exists(os.path.join(recovery_stage, "part.bin")))


if __name__ == "__main__":
    unittest.main()
