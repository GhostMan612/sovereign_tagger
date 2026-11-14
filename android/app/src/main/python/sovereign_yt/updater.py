# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import ast
import hashlib
import io
import json
import os
import posixpath
import re
import shutil
import ssl
import sys
import tarfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from sovereign_yt import overlay_bootstrap

GITHUB_LATEST_RELEASE_URL = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
TRUSTED_RELEASE_HOSTS = frozenset(
    {
        "api.github.com",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "codeload.github.com",
    }
)
APK_MANAGED_PACKAGES = ("mutagen", "lyricsgenius")

MAX_RELEASE_JSON_BYTES = 2 * 1024 * 1024
MAX_CHECKSUM_FILE_BYTES = 512 * 1024
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 4000
MAX_UNCOMPRESSED_BYTES = 80 * 1024 * 1024
MAX_MEMBER_BYTES = 8 * 1024 * 1024
MAX_MEMBER_PATH_LEN = 240
MAX_MEMBER_DEPTH = 16
MAX_COMPRESSION_RATIO = 40
MAX_REDIRECTS = 5
HTTP_TIMEOUT_SECONDS = 25

_FORBIDDEN_FILE_EXTENSIONS = (".so", ".dll", ".exe", ".dylib", ".bat", ".cmd", ".sh", ".bin", ".pyc", ".pyo")
_BINARY_MAGIC_PREFIXES = (b"\x7fELF", b"MZ\x90\x00")
_REQUIRES_PYTHON_MIN_RE = re.compile(r">=\s*(\d+)\.(\d+)")
_WRAPPER_DIR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
_CHECKSUM_LINE_RE = re.compile(r"^([0-9a-fA-F]{64})\s+\*?(.+)$")

_TRANSACTION_LOCK = threading.RLock()


class UpdaterSecurityError(ValueError):
    pass


class _TrustedRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        resolved = urllib.parse.urljoin(req.full_url, newurl)
        validate_trusted_https_url(resolved)
        return super().redirect_request(req, fp, code, msg, headers, resolved)


def validate_trusted_https_url(url):
    if not isinstance(url, str) or not url.strip():
        raise UpdaterSecurityError("Empty release URL rejected.")
    parsed = urllib.parse.urlparse(url.strip())
    if parsed.scheme.lower() != "https":
        raise UpdaterSecurityError(f"Non-HTTPS URL rejected: {url}")
    if parsed.username or parsed.password:
        raise UpdaterSecurityError("Credentials in URL are prohibited.")
    host = (parsed.hostname or "").lower()
    if host not in TRUSTED_RELEASE_HOSTS:
        raise UpdaterSecurityError(f"Untrusted host rejected: {host or '<empty>'}")
    return url.strip()


def _default_http_get_bytes(url, max_bytes, accept="application/octet-stream"):
    clean_url = validate_trusted_https_url(url)
    context = ssl.create_default_context()
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=context),
        _TrustedRedirectHandler(),
    )
    request = urllib.request.Request(
        clean_url,
        headers={
            "User-Agent": "SovereignTagger-OverlayUpdater/1.0",
            "Accept": accept,
        },
        method="GET",
    )
    with opener.open(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
        final_url = response.geturl()
        validate_trusted_https_url(final_url)
        content_length = response.headers.get("Content-Length")
        if content_length is not None:
            try:
                if int(content_length) > max_bytes:
                    raise UpdaterSecurityError(f"Remote payload exceeds limit ({content_length} > {max_bytes}).")
            except ValueError:
                pass
        buf = bytearray()
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            buf.extend(chunk)
            if len(buf) > max_bytes:
                raise UpdaterSecurityError(f"Downloaded payload exceeds safety ceiling ({max_bytes} bytes).")
    return bytes(buf)


def _fetch_checked(fetcher, url, max_bytes, accept="application/octet-stream"):
    clean_url = validate_trusted_https_url(url)
    if fetcher is None:
        return _default_http_get_bytes(clean_url, max_bytes, accept=accept)
    raw = fetcher(clean_url, max_bytes)
    if not isinstance(raw, (bytes, bytearray)):
        raise UpdaterSecurityError("Release fetcher must return raw bytes.")
    if len(raw) > max_bytes:
        raise UpdaterSecurityError(f"Payload exceeds safety ceiling ({len(raw)} > {max_bytes}).")
    return bytes(raw)


def _parse_checksums(sums_text, target_asset_name="yt-dlp.tar.gz"):
    for line in sums_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        match = _CHECKSUM_LINE_RE.match(stripped)
        if not match:
            continue
        digest = match.group(1).lower()
        name = match.group(2).strip()
        if name == target_asset_name or posixpath.basename(name) == target_asset_name:
            return digest
    raise UpdaterSecurityError(f"SHA2-256SUMS missing entry for {target_asset_name}.")


def _extract_release_metadata(release_payload):
    if not isinstance(release_payload, dict):
        raise UpdaterSecurityError("Release metadata is not a JSON object.")
    if release_payload.get("draft") is True:
        raise UpdaterSecurityError("Refusing draft yt-dlp release.")
    if release_payload.get("prerelease") is True:
        raise UpdaterSecurityError("Refusing prerelease yt-dlp build.")

    tag_name = str(release_payload.get("tag_name") or "").strip()
    release_ver = overlay_bootstrap.normalize_calver(tag_name)
    if overlay_bootstrap.parse_calver(release_ver) is None:
        raise UpdaterSecurityError(f"Release tag is not valid CalVer: {tag_name or '<empty>'}")

    assets = release_payload.get("assets")
    if not isinstance(assets, list):
        raise UpdaterSecurityError("Release metadata missing assets array.")

    archive_url = None
    sums_url = None
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        name = str(asset.get("name") or "").strip()
        dl_url = str(asset.get("browser_download_url") or "").strip()
        if not dl_url:
            continue
        validate_trusted_https_url(dl_url)
        if name == "yt-dlp.tar.gz":
            archive_url = dl_url
        elif name == "SHA2-256SUMS":
            sums_url = dl_url

    if not archive_url:
        raise UpdaterSecurityError("Official release is missing verified yt-dlp.tar.gz asset.")
    if not sums_url:
        raise UpdaterSecurityError("Official release is missing SHA2-256SUMS asset.")

    return release_ver, archive_url, sums_url


def _validate_tar_member_name(name, is_dir=False):
    if not isinstance(name, str) or not name or "\x00" in name or "\\" in name:
        raise UpdaterSecurityError("Archive member path contains forbidden characters.")
    if is_dir and name in (".", "./"):
        return []
    if len(name) > MAX_MEMBER_PATH_LEN:
        raise UpdaterSecurityError("Archive member path exceeds length ceiling.")
    if name.startswith("/") or (len(name) >= 2 and name[1] == ":"):
        raise UpdaterSecurityError(f"Absolute archive member path rejected: {name}")
    stripped = name[2:] if name.startswith("./") else name
    if not stripped:
        return []
    parts = stripped.split("/")
    if is_dir and parts and parts[-1] == "":
        parts = parts[:-1]
    if any(p == "" for p in parts):
        raise UpdaterSecurityError(f"Malformed empty path segment rejected: {name}")
    if len(parts) > MAX_MEMBER_DEPTH:
        raise UpdaterSecurityError(f"Archive path nesting exceeds limit: {name}")
    for part in parts:
        if part in (".", "..") or any(ord(ch) < 32 for ch in part):
            raise UpdaterSecurityError(f"Unsafe path segment rejected: {name}")
    return parts


def _detect_package_prefix(member_records):
    candidates = set()
    for parts, is_dir in member_records:
        if is_dir or len(parts) < 2:
            continue
        if parts[0] == "yt_dlp" and parts[1] == "__init__.py":
            candidates.add(())
        elif len(parts) >= 3 and _WRAPPER_DIR_RE.match(parts[0]) and parts[1] == "yt_dlp" and parts[2] == "__init__.py":
            candidates.add((parts[0],))
    if len(candidates) != 1:
        raise UpdaterSecurityError("Archive does not contain an unambiguous yt_dlp package root.")
    return next(iter(candidates))


def _check_requires_python(toml_bytes):
    text = toml_bytes.decode("utf-8", errors="replace")
    for line in text.splitlines():
        clean = line.strip()
        if clean.startswith("requires-python"):
            match = _REQUIRES_PYTHON_MIN_RE.search(clean)
            if match:
                req = (int(match.group(1)), int(match.group(2)))
                if sys.version_info[:2] < req:
                    raise UpdaterSecurityError(
                        f"yt-dlp release requires Python {req[0]}.{req[1]}+, runtime is {sys.version_info[0]}.{sys.version_info[1]}."
                    )
                return [req[0], req[1]]
    return None


def _safe_extract_ytdlp_from_tarball(archive_bytes, dest_stage_dir):
    compressed_size = len(archive_bytes)
    if compressed_size == 0 or compressed_size > MAX_ARCHIVE_BYTES:
        raise UpdaterSecurityError("Archive compressed size is invalid or exceeds ceiling.")

    os.makedirs(dest_stage_dir, exist_ok=True)
    stage_real = os.path.realpath(dest_stage_dir)

    try:
        tf_stream = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz")
    except (tarfile.TarError, EOFError, OSError) as exc:
        raise UpdaterSecurityError(f"Invalid gzip tarball archive: {exc}") from exc

    member_records = []
    parsed_members = []
    total_uncompressed = 0

    with tf_stream as tf:
        for member in tf:
            if len(parsed_members) >= MAX_ARCHIVE_MEMBERS:
                raise UpdaterSecurityError(f"Archive exceeds maximum member limit ({MAX_ARCHIVE_MEMBERS}).")
            if member.issym() or member.islnk():
                raise UpdaterSecurityError(f"Symlink/hardlink member prohibited: {member.name}")
            if not (member.isfile() or member.isdir()):
                raise UpdaterSecurityError(f"Special filesystem entry prohibited: {member.name}")

            parts = _validate_tar_member_name(member.name, is_dir=member.isdir())
            if member.isfile():
                if member.size < 0 or member.size > MAX_MEMBER_BYTES:
                    raise UpdaterSecurityError(f"Archive file exceeds member size cap: {member.name}")
                total_uncompressed += member.size
                if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
                    raise UpdaterSecurityError("Archive uncompressed payload exceeds ceiling.")
                ratio_floor = max(compressed_size, 64 * 1024)
                if total_uncompressed > ratio_floor * MAX_COMPRESSION_RATIO:
                    raise UpdaterSecurityError("Archive expansion ratio exceeds bomb threshold.")

            if parts:
                member_records.append((parts, member.isdir()))
                parsed_members.append((member, parts))

        prefix_tuple = _detect_package_prefix(member_records)
        prefix_len = len(prefix_tuple)
        requires_py = None
        asset_rel_paths = []
        extracted_files = 0

        for member, parts in parsed_members:
            if prefix_tuple and tuple(parts[:prefix_len]) != prefix_tuple:
                continue
            sub_parts = parts[prefix_len:]
            if not sub_parts:
                continue

            if not member.isdir() and sub_parts == ["pyproject.toml"]:
                extracted_stream = tf.extractfile(member)
                if extracted_stream is not None:
                    raw_toml = extracted_stream.read(256 * 1024)
                    requires_py = _check_requires_python(raw_toml)
                continue

            if sub_parts[0] != "yt_dlp":
                continue

            if "__pycache__" in sub_parts:
                raise UpdaterSecurityError("Archive must not pre-bundle __pycache__ directories.")

            target_path = os.path.join(stage_real, *sub_parts)
            target_abs = os.path.abspath(target_path)
            if not overlay_bootstrap.is_path_within(stage_real, target_abs):
                raise UpdaterSecurityError(f"Extracted member escapes staging root: {member.name}")

            if member.isdir():
                os.makedirs(target_abs, exist_ok=True)
                continue

            lower_name = sub_parts[-1].lower()
            if lower_name.endswith(_FORBIDDEN_FILE_EXTENSIONS):
                raise UpdaterSecurityError(f"Prohibited binary/bytecode artifact in archive: {'/'.join(sub_parts)}")

            os.makedirs(os.path.dirname(target_abs), exist_ok=True)
            extracted_stream = tf.extractfile(member)
            if extracted_stream is None:
                raise UpdaterSecurityError(f"Unreadable file entry in archive: {member.name}")

            bytes_written = 0
            first_bytes = None
            with open(target_abs, "wb") as out_handle:
                while True:
                    chunk = extracted_stream.read(65536)
                    if not chunk:
                        break
                    if first_bytes is None:
                        first_bytes = chunk[:8]
                        for magic in _BINARY_MAGIC_PREFIXES:
                            if first_bytes.startswith(magic):
                                raise UpdaterSecurityError(f"Native executable payload prohibited: {'/'.join(sub_parts)}")
                    bytes_written += len(chunk)
                    if bytes_written > MAX_MEMBER_BYTES:
                        raise UpdaterSecurityError(f"Extracted file exceeded size limit: {member.name}")
                    out_handle.write(chunk)
                out_handle.flush()
                os.fsync(out_handle.fileno())

            extracted_files += 1
            if not lower_name.endswith((".py", ".pyi")):
                rel_asset = "/".join(sub_parts[1:])
                if rel_asset:
                    asset_rel_paths.append(rel_asset)

    if extracted_files < 2:
        raise UpdaterSecurityError("Staged yt_dlp package is incomplete.")

    pkg_dir = os.path.join(stage_real, "yt_dlp")
    init_py = os.path.join(pkg_dir, "__init__.py")
    version_py = os.path.join(pkg_dir, "version.py")
    if not os.path.isfile(init_py) or not os.path.isfile(version_py):
        raise UpdaterSecurityError("Staged package is missing yt_dlp/__init__.py or yt_dlp/version.py.")

    with open(init_py, "r", encoding="utf-8") as handle:
        ast.parse(handle.read(), filename=init_py)
    with open(version_py, "r", encoding="utf-8") as handle:
        version_source = handle.read()
    staged_version = overlay_bootstrap.extract_version_from_ast(version_source)
    if not staged_version or overlay_bootstrap.parse_calver(staged_version) is None:
        raise UpdaterSecurityError("Staged yt_dlp/version.py does not expose a valid CalVer __version__.")

    return {
        "package_dir": pkg_dir,
        "staged_version": overlay_bootstrap.normalize_calver(staged_version),
        "requires_python": {"min": requires_py} if requires_py else None,
        "required_assets": sorted(asset_rel_paths),
        "extracted_files": extracted_files,
    }


def _resolve_overlay_root_or_raise(overlay_root=None):
    if isinstance(overlay_root, str) and overlay_root.strip():
        return overlay_root.strip()
    state = overlay_bootstrap.get_runtime_status()
    from_state = state.get("overlay_root")
    if isinstance(from_state, str) and from_state.strip():
        return from_state.strip()
    env_root = os.environ.get("SOVEREIGN_PY_OVERLAY_DIR", "")
    if env_root.strip():
        return env_root.strip()
    raise ValueError("Explicit overlay_root is required for updater operations.")


def _cleanup_stale_staging(staging_dir):
    if not os.path.isdir(staging_dir):
        return
    for entry in os.listdir(staging_dir):
        full = os.path.join(staging_dir, entry)
        try:
            if os.path.isdir(full) and not os.path.islink(full):
                shutil.rmtree(full, ignore_errors=True)
            else:
                os.unlink(full)
        except OSError:
            pass


def _prune_unused_slots(slots_dir, manifest):
    if not os.path.isdir(slots_dir):
        return
    pinned = {
        manifest.get("active_slot"),
        manifest.get("previous_slot"),
        manifest.get("pending_slot"),
        manifest.get("last_known_good_slot"),
    }
    pinned.discard(None)
    for entry in os.listdir(slots_dir):
        if entry in pinned:
            continue
        candidate = os.path.join(slots_dir, entry)
        try:
            if os.path.isdir(candidate) and not os.path.islink(candidate):
                shutil.rmtree(candidate, ignore_errors=True)
        except OSError:
            pass


def _floor_version(runtime_state, manifest, bundled_version_hint=None):
    candidates = [
        bundled_version_hint or "",
        runtime_state.get("bundled_version") or "",
        manifest.get("bundled_version") or "",
        runtime_state.get("active_version") or "",
        manifest.get("active_version") or "",
        manifest.get("pending_version") or "",
    ]
    best_ver = ""
    best_tuple = None
    for cand in candidates:
        norm = overlay_bootstrap.normalize_calver(cand)
        parsed = overlay_bootstrap.parse_calver(norm)
        if parsed is not None and (best_tuple is None or parsed > best_tuple):
            best_tuple = parsed
            best_ver = norm
    return best_ver, best_tuple


def _build_status_payload(paths, runtime_state, manifest):
    bundled = (
        runtime_state.get("bundled_version")
        or manifest.get("bundled_version")
        or ""
    )
    active_source = runtime_state.get("active_source") or ("overlay" if manifest.get("active_slot") else "bundled")
    active_version = runtime_state.get("active_version") or manifest.get("active_version") or bundled
    pending_slot = manifest.get("pending_slot")
    pending_version = manifest.get("pending_version")
    recovery_required = bool(manifest.get("recovery_required") or runtime_state.get("recovery_required"))
    last_error = manifest.get("last_error") or runtime_state.get("last_error")
    return {
        "status": "success",
        "bundled_version": bundled,
        "active_version": active_version,
        "active_source": active_source,
        "active_slot": runtime_state.get("active_slot") or manifest.get("active_slot"),
        "previous_slot": manifest.get("previous_slot"),
        "previous_version": manifest.get("previous_version"),
        "pending_slot": pending_slot,
        "pending_version": pending_version,
        "restart_required": bool(pending_slot and pending_version),
        "recovery_required": recovery_required,
        "rolled_back": bool(runtime_state.get("rolled_back") or manifest.get("rolled_back_from")),
        "rolled_back_from": runtime_state.get("rolled_back_from") or manifest.get("rolled_back_from"),
        "last_error": last_error,
        "premature_import": bool(runtime_state.get("premature_import", False)),
        "origin_file": runtime_state.get("origin_file") or "",
        "selected_path": runtime_state.get("selected_path") or "",
        "overlay_root": paths["root"],
        "apk_managed_packages": list(APK_MANAGED_PACKAGES),
        "transaction_state": str(manifest.get("transaction", {}).get("state") or "idle"),
    }


def get_status(overlay_root=None, bundled_version_hint=None):
    with _TRANSACTION_LOCK:
        root = _resolve_overlay_root_or_raise(overlay_root)
        paths = overlay_bootstrap.resolve_overlay_paths(root)
        runtime_state = overlay_bootstrap.get_runtime_status(paths["root"])
        hint = overlay_bootstrap.normalize_calver(
            bundled_version_hint or runtime_state.get("bundled_version") or ""
        )
        try:
            manifest, _ = overlay_bootstrap.load_manifest(paths["manifest"], hint)
        except Exception as exc:
            manifest = overlay_bootstrap.default_manifest(hint)
            manifest["recovery_required"] = True
            manifest["last_error"] = f"Overlay manifest unreadable: {exc}"
        return json.dumps(_build_status_payload(paths, runtime_state, manifest))


def execute_scorched_earth(
    overlay_root=None,
    fetcher=None,
    bundled_version_hint=None,
    release_url=GITHUB_LATEST_RELEASE_URL,
    commit_hook=None,
):
    with _TRANSACTION_LOCK:
        root = _resolve_overlay_root_or_raise(overlay_root)
        paths = overlay_bootstrap.resolve_overlay_paths(root)
        os.makedirs(paths["slots"], exist_ok=True)
        os.makedirs(paths["staging"], exist_ok=True)

        runtime_state = overlay_bootstrap.get_runtime_status(paths["root"])
        hint = overlay_bootstrap.normalize_calver(
            bundled_version_hint or runtime_state.get("bundled_version") or ""
        )
        try:
            manifest, _ = overlay_bootstrap.load_manifest(paths["manifest"], hint)
        except Exception as exc:
            corrupt_path = f"{paths['manifest']}.corrupt.{int(time.time())}"
            try:
                if os.path.exists(paths["manifest"]):
                    shutil.copyfile(paths["manifest"], corrupt_path)
            except OSError:
                pass
            manifest = overlay_bootstrap.default_manifest(hint)
            manifest["last_error"] = f"Corrupted manifest quarantined before update: {exc}"

        _cleanup_stale_staging(paths["staging"])

        tx_id = uuid.uuid4().hex[:12]
        stage_tx_dir = os.path.join(paths["staging"], tx_id)
        commit_phase = False

        try:
            release_bytes = _fetch_checked(
                fetcher,
                release_url,
                MAX_RELEASE_JSON_BYTES,
                accept="application/vnd.github+json",
            )
            release_payload = json.loads(release_bytes.decode("utf-8"))
            release_ver, archive_url, sums_url = _extract_release_metadata(release_payload)

            floor_ver, floor_tuple = _floor_version(runtime_state, manifest, hint)
            cand_tuple = overlay_bootstrap.parse_calver(release_ver)
            if cand_tuple is None:
                raise UpdaterSecurityError(f"Release version is invalid CalVer: {release_ver}")

            if floor_tuple is not None and cand_tuple < floor_tuple:
                raise UpdaterSecurityError(
                    f"Rejected downgrade attempt: release {release_ver} is older than current {floor_ver}."
                )

            pending_ver = overlay_bootstrap.normalize_calver(manifest.get("pending_version") or "")
            if pending_ver and pending_ver == release_ver and manifest.get("pending_slot") and not manifest.get("recovery_required"):
                payload = _build_status_payload(paths, runtime_state, manifest)
                payload["version"] = release_ver
                payload["slot_id"] = manifest.get("pending_slot")
                payload["message"] = (
                    f"yt-dlp {release_ver} is already staged. Restart Sovereign Tagger to activate."
                )
                return json.dumps(payload)

            active_ver = overlay_bootstrap.normalize_calver(
                runtime_state.get("active_version") or manifest.get("active_version") or hint
            )
            if active_ver and active_ver == release_ver and not manifest.get("recovery_required"):
                payload = _build_status_payload(paths, runtime_state, manifest)
                payload["up_to_date"] = True
                payload["version"] = release_ver
                payload["message"] = f"yt-dlp {release_ver} is already current (no overlay change needed)."
                return json.dumps(payload)

            sums_bytes = _fetch_checked(fetcher, sums_url, MAX_CHECKSUM_FILE_BYTES, accept="text/plain")
            expected_sha256 = _parse_checksums(sums_bytes.decode("utf-8"), "yt-dlp.tar.gz")
            archive_bytes = _fetch_checked(
                fetcher,
                archive_url,
                MAX_ARCHIVE_BYTES,
                accept="application/octet-stream",
            )
            actual_sha256 = hashlib.sha256(archive_bytes).hexdigest().lower()
            if actual_sha256 != expected_sha256:
                raise UpdaterSecurityError(
                    f"Archive SHA-256 verification failed (expected {expected_sha256[:12]}..., got {actual_sha256[:12]}...)."
                )

            staged = _safe_extract_ytdlp_from_tarball(archive_bytes, stage_tx_dir)
            if staged["staged_version"] != release_ver:
                raise UpdaterSecurityError(
                    f"Package version ({staged['staged_version']}) does not match release tag ({release_ver})."
                )

            tree_sha256, file_count = overlay_bootstrap.compute_package_tree_sha256(staged["package_dir"])
            slot_id = f"{release_ver}-{tx_id[:8]}"
            slot_dir = overlay_bootstrap.resolve_contained_slot(paths["slots"], slot_id)
            if os.path.exists(slot_dir):
                shutil.rmtree(slot_dir)
            os.makedirs(slot_dir, exist_ok=True)
            target_pkg_dir = os.path.join(slot_dir, "yt_dlp")
            os.replace(staged["package_dir"], target_pkg_dir)

            slot_meta = {
                "schema_version": overlay_bootstrap.SCHEMA_VERSION,
                "slot_id": slot_id,
                "package": "yt_dlp",
                "version": release_ver,
                "archive_sha256": actual_sha256,
                "tree_sha256": tree_sha256,
                "file_count": file_count,
                "bundled_version_at_stage": hint or runtime_state.get("bundled_version") or "",
                "requires_python": staged["requires_python"],
                "required_assets": staged["required_assets"],
                "source_url": archive_url,
                "created_at": int(time.time()),
            }
            commit_phase = True
            overlay_bootstrap.atomic_write_json(os.path.join(slot_dir, "slot.json"), slot_meta)
            overlay_bootstrap.validate_slot_directory(paths["slots"], slot_id, release_ver, verify_tree_hash=True)

            now_ts = int(time.time())
            manifest["pending_slot"] = slot_id
            manifest["pending_version"] = release_ver
            manifest["pending_sha256"] = actual_sha256
            manifest["pending_source_url"] = archive_url
            manifest["recovery_required"] = False
            manifest["last_error"] = None
            manifest["transaction"] = {
                "id": tx_id,
                "state": "pending_activation",
                "started_at": now_ts,
                "updated_at": now_ts,
                "target_version": release_ver,
            }

            if callable(commit_hook):
                commit_hook(paths, manifest, slot_dir)

            overlay_bootstrap.atomic_write_json(paths["manifest"], manifest)
            _prune_unused_slots(paths["slots"], manifest)
            _cleanup_stale_staging(paths["staging"])

            payload = _build_status_payload(paths, runtime_state, manifest)
            payload["version"] = release_ver
            payload["slot_id"] = slot_id
            payload["restart_required"] = True
            payload["message"] = (
                f"yt-dlp {release_ver} verified and staged in overlay slot {slot_id}. "
                f"Restart Sovereign Tagger to activate."
            )
            return json.dumps(payload)

        except Exception as exc:
            should_require_recovery = bool(commit_phase)
            if should_require_recovery:
                manifest["pending_slot"] = None
                manifest["pending_version"] = None
                manifest["pending_sha256"] = None
                manifest["pending_source_url"] = None
                manifest["recovery_required"] = True
                manifest["last_error"] = str(exc)
                manifest["transaction"]["state"] = "recovery_required"
                manifest["transaction"]["updated_at"] = int(time.time())
                try:
                    overlay_bootstrap.atomic_write_json(paths["manifest"], manifest)
                except OSError:
                    pass
            else:
                try:
                    shutil.rmtree(stage_tx_dir, ignore_errors=True)
                except OSError:
                    pass

            err_payload = _build_status_payload(paths, runtime_state, manifest)
            err_payload["status"] = "error"
            err_payload["recovery_required"] = bool(manifest.get("recovery_required") or should_require_recovery)
            err_payload["message"] = str(exc)
            return json.dumps(err_payload)


def execute_full_scorched_earth(overlay_root=None, bundled_version_hint=None):
    with _TRANSACTION_LOCK:
        root = _resolve_overlay_root_or_raise(overlay_root)
        paths = overlay_bootstrap.resolve_overlay_paths(root)
        runtime_state = overlay_bootstrap.get_runtime_status(paths["root"])
        hint = overlay_bootstrap.normalize_calver(
            bundled_version_hint or runtime_state.get("bundled_version") or ""
        )
        try:
            manifest, _ = overlay_bootstrap.load_manifest(paths["manifest"], hint)
        except Exception:
            manifest = overlay_bootstrap.default_manifest(hint)

        payload = _build_status_payload(paths, runtime_state, manifest)
        payload["status"] = "requires_apk_update"
        payload["core_updatable"] = True
        payload["apk_managed_packages"] = list(APK_MANAGED_PACKAGES)
        payload["message"] = (
            "mutagen and lyricsgenius are pinned in the APK and require a new APK build to update. "
            "Use Check for yt-dlp Update for standalone yt-dlp updates."
        )
        return json.dumps(payload)
