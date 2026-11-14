# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import hashlib
import io
import json
import os
import shutil
import struct
import tarfile

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


def _make_fixture_rsa_key(seed_tag=9, label="acceptance-fixture-rsa"):
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


def _subpkt(sub_type, val):
    return bytes([1 + len(val), sub_type]) + val


def _sign_openpgp_v4_rsa(data_bytes, full_key):
    hashed_blob = b"".join(
        [
            _subpkt(2, struct.pack(">I", 1730000000)),
            _subpkt(33, b"\x04" + bytes.fromhex(full_key["fingerprint"])),
            _subpkt(16, bytes.fromhex(full_key["key_id"])),
        ]
    )
    header = bytes([4, 0x00, 1, 10]) + struct.pack(">H", len(hashed_blob)) + hashed_blob
    hash_fn, der_prefix = updater._PGP_DIGEST_INFOS[10]
    hasher = hash_fn()
    hasher.update(data_bytes)
    hasher.update(header)
    hasher.update(b"\x04\xff" + struct.pack(">I", len(header)))
    digest = hasher.digest()
    k_bytes = (full_key["n"].bit_length() + 7) // 8
    t_bytes = der_prefix + digest
    em = b"\x00\x01" + (b"\xff" * (k_bytes - len(t_bytes) - 3)) + b"\x00" + t_bytes
    sig_int = pow(int.from_bytes(em, "big"), full_key["d"], full_key["n"])
    body = header + struct.pack(">H", 0) + digest[:2] + _encode_mpi(sig_int)
    pkt_len = len(body)
    if pkt_len < 192:
        len_hdr = bytes([pkt_len])
    elif pkt_len < 8384:
        adj = pkt_len - 192
        len_hdr = bytes([192 + (adj >> 8), adj & 0xFF])
    else:
        len_hdr = b"\xff" + struct.pack(">I", pkt_len)
    return b"\xc2" + len_hdr + body


_FIXTURE_PGP_KEY = _make_fixture_rsa_key()
_FIXTURE_PINNED_KEYS = ({k: _FIXTURE_PGP_KEY[k] for k in ("label", "fingerprint", "key_id", "e", "n")},)


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
    sig_url = f"https://github.com/yt-dlp/yt-dlp/releases/download/{version}/SHA2-256SUMS.sig"
    release_doc = json.dumps(
        {
            "tag_name": version,
            "draft": False,
            "prerelease": False,
            "assets": [
                {"name": "yt-dlp.tar.gz", "browser_download_url": archive_url},
                {"name": "SHA2-256SUMS", "browser_download_url": sums_url},
                {"name": "SHA2-256SUMS.sig", "browser_download_url": sig_url},
            ],
        }
    ).encode("utf-8")
    sums_bytes = f"{digest}  yt-dlp.tar.gz\n".encode("utf-8")
    sig_bytes = _sign_openpgp_v4_rsa(sums_bytes, _FIXTURE_PGP_KEY)

    def fetcher(url, _max_bytes):
        if url == updater.GITHUB_LATEST_RELEASE_URL:
            return release_doc
        if url == sig_url:
            return sig_bytes
        if url == sums_url:
            return sums_bytes
        if url == archive_url:
            return tar_bytes
        raise RuntimeError(f"Unexpected acceptance fetcher URL: {url}")

    return updater.execute_scorched_earth(
        overlay_root=overlay_root,
        fetcher=fetcher,
        bundled_version_hint=bundled_version_hint,
        pinned_keys=_FIXTURE_PINNED_KEYS,
    )


def stage_live_github_release(overlay_root):
    saved_state = overlay_bootstrap._RUNTIME_STATE
    try:
        overlay_bootstrap._RUNTIME_STATE = {
            "initialized": True,
            "overlay_root": os.path.realpath(os.path.abspath(overlay_root)),
            "bundled_version": "2026.01.01",
            "active_source": "bundled",
            "active_version": "2026.01.01",
        }
        return updater.execute_scorched_earth(
            overlay_root=overlay_root,
            bundled_version_hint="2026.01.01",
        )
    finally:
        overlay_bootstrap._RUNTIME_STATE = saved_state


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
