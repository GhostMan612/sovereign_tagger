# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import ast
import hashlib
import importlib
import importlib.util
import json
import marshal
import os
import re
import shutil
import sys
import threading
import time
import zipfile

SCHEMA_VERSION = 1
_OVERLAY_SUBDIR = "sovereign_py_overlay"
_SLOTS_SUBDIR = "slots"
_STAGING_SUBDIR = "staging"
_MANIFEST_FILENAME = "active.json"
_SLOT_METADATA_FILENAME = "slot.json"
_MAX_MANIFEST_BYTES = 512 * 1024
_SLOT_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_CALVER_RE = re.compile(r"^v?(\d{4})\.(\d{1,2})\.(\d{1,2})(?:\.(\d+))?(?:post(\d+))?$")
_HEX_SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
_IGNORED_CACHE_DIRS = {"__pycache__"}
_IGNORED_CACHE_EXTS = (".pyc", ".pyo")

_BOOTSTRAP_LOCK = threading.RLock()
_RUNTIME_STATE = None


def parse_calver(version_text):
    if not isinstance(version_text, str):
        return None
    normalized = version_text.strip()
    if not normalized:
        return None
    match = _CALVER_RE.match(normalized)
    if not match:
        return None
    year = int(match.group(1))
    month = int(match.group(2))
    day = int(match.group(3))
    patch = int(match.group(4)) if match.group(4) is not None else 0
    post = int(match.group(5)) if match.group(5) is not None else 0
    if month < 1 or month > 12 or day < 1 or day > 31:
        return None
    return (year, month, day, patch, post)


def normalize_calver(version_text):
    if not isinstance(version_text, str):
        return ""
    cleaned = version_text.strip()
    if cleaned.startswith(("v", "V")):
        cleaned = cleaned[1:]
    return cleaned


def resolve_overlay_paths(overlay_root):
    if not isinstance(overlay_root, str) or not overlay_root.strip():
        raise ValueError("Explicit overlay_root path is required.")
    root_real = os.path.realpath(os.path.abspath(overlay_root.strip()))
    return {
        "root": root_real,
        "slots": os.path.join(root_real, _SLOTS_SUBDIR),
        "staging": os.path.join(root_real, _STAGING_SUBDIR),
        "manifest": os.path.join(root_real, _MANIFEST_FILENAME),
    }


def is_path_within(base_dir, target_path):
    try:
        base_real = os.path.realpath(os.path.abspath(base_dir))
        target_real = os.path.realpath(os.path.abspath(target_path))
        return os.path.commonpath([base_real, target_real]) == base_real
    except (ValueError, OSError):
        return False


def resolve_contained_slot(slots_dir, slot_id):
    if not isinstance(slot_id, str) or not _SLOT_NAME_RE.match(slot_id):
        raise ValueError("Invalid overlay slot identifier.")
    if os.path.islink(slots_dir):
        raise ValueError("Overlay slots directory must not be a symlink.")
    candidate = os.path.join(slots_dir, slot_id)
    if os.path.islink(candidate):
        raise ValueError("Overlay slot directory must not be a symlink.")
    slots_real = os.path.realpath(os.path.abspath(slots_dir))
    cand_real = os.path.realpath(os.path.abspath(candidate))
    if cand_real == slots_real or os.path.commonpath([slots_real, cand_real]) != slots_real:
        raise ValueError("Overlay slot path escapes overlay container.")
    return cand_real


def compute_package_tree_sha256(package_dir):
    if not os.path.isdir(package_dir) or os.path.islink(package_dir):
        raise ValueError("Package directory is missing or invalid.")
    pkg_real = os.path.realpath(package_dir)
    entries = []
    for dirpath, dirnames, filenames in os.walk(pkg_real, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d not in _IGNORED_CACHE_DIRS)
        for dname in dirnames:
            full_dir = os.path.join(dirpath, dname)
            if os.path.islink(full_dir):
                raise ValueError(f"Symlink prohibited in overlay slot: {full_dir}")
        for fname in sorted(filenames):
            if fname.endswith(_IGNORED_CACHE_EXTS):
                continue
            full_file = os.path.join(dirpath, fname)
            if os.path.islink(full_file) or not os.path.isfile(full_file):
                raise ValueError(f"Non-regular file prohibited in overlay slot: {full_file}")
            if not is_path_within(pkg_real, full_file):
                raise ValueError(f"File escapes overlay slot: {full_file}")
            rel_path = os.path.relpath(full_file, pkg_real).replace("\\", "/")
            file_hash = hashlib.sha256()
            with open(full_file, "rb") as handle:
                while True:
                    chunk = handle.read(65536)
                    if not chunk:
                        break
                    file_hash.update(chunk)
            entries.append(f"{rel_path}:{file_hash.hexdigest()}")
    entries.sort()
    tree_hash = hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest()
    return tree_hash, len(entries)


def extract_version_from_ast(source_text):
    tree = ast.parse(source_text)
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "__version__":
                    val = ast.literal_eval(node.value)
                    if isinstance(val, str):
                        return val.strip()
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name) and node.target.id == "__version__" and node.value is not None:
                val = ast.literal_eval(node.value)
                if isinstance(val, str):
                    return val.strip()
    return None


def validate_slot_directory(slots_dir, slot_id, expected_version=None, verify_tree_hash=True):
    slot_dir = resolve_contained_slot(slots_dir, slot_id)
    if not os.path.isdir(slot_dir):
        raise ValueError(f"Overlay slot missing on disk: {slot_id}")

    metadata_path = os.path.join(slot_dir, _SLOT_METADATA_FILENAME)
    if os.path.islink(metadata_path) or not os.path.isfile(metadata_path):
        raise ValueError(f"Overlay slot metadata missing: {slot_id}")

    with open(metadata_path, "r", encoding="utf-8") as handle:
        slot_meta = json.load(handle)

    if not isinstance(slot_meta, dict):
        raise ValueError("Invalid slot metadata structure.")
    if slot_meta.get("slot_id") != slot_id:
        raise ValueError("Slot metadata identifier mismatch.")
    if slot_meta.get("package") != "yt_dlp":
        raise ValueError("Slot metadata package identity mismatch.")

    slot_version = normalize_calver(str(slot_meta.get("version") or ""))
    if parse_calver(slot_version) is None:
        raise ValueError("Slot metadata version is not valid CalVer.")
    if expected_version and slot_version != normalize_calver(expected_version):
        raise ValueError(f"Slot version {slot_version} does not match expected {expected_version}.")

    tree_sha = str(slot_meta.get("tree_sha256") or "")
    if not _HEX_SHA256_RE.match(tree_sha):
        raise ValueError("Slot metadata missing valid tree digest.")

    requires_py = slot_meta.get("requires_python")
    if isinstance(requires_py, dict):
        min_ver = requires_py.get("min")
        if isinstance(min_ver, list) and len(min_ver) >= 2:
            if sys.version_info[:2] < (int(min_ver[0]), int(min_ver[1])):
                raise ValueError(
                    f"Slot requires Python {min_ver[0]}.{min_ver[1]}+, runtime is {sys.version_info[0]}.{sys.version_info[1]}."
                )

    pkg_dir = os.path.join(slot_dir, "yt_dlp")
    init_py = os.path.join(pkg_dir, "__init__.py")
    version_py = os.path.join(pkg_dir, "version.py")
    if not os.path.isdir(pkg_dir) or os.path.islink(pkg_dir):
        raise ValueError("Overlay slot missing yt_dlp directory.")
    if not os.path.isfile(init_py) or os.path.islink(init_py):
        raise ValueError("Overlay slot missing yt_dlp/__init__.py.")
    if not os.path.isfile(version_py) or os.path.islink(version_py):
        raise ValueError("Overlay slot missing yt_dlp/version.py.")

    with open(init_py, "r", encoding="utf-8") as handle:
        ast.parse(handle.read(), filename=init_py)
    with open(version_py, "r", encoding="utf-8") as handle:
        ver_source = handle.read()
    parsed_version = extract_version_from_ast(ver_source)
    if normalize_calver(parsed_version or "") != slot_version:
        raise ValueError(f"version.py ({parsed_version}) does not match slot version ({slot_version}).")

    required_assets = slot_meta.get("required_assets")
    if isinstance(required_assets, list):
        for rel_asset in required_assets:
            if not isinstance(rel_asset, str) or not rel_asset or ".." in rel_asset.split("/"):
                raise ValueError("Invalid required_assets entry in slot metadata.")
            asset_full = os.path.join(pkg_dir, *rel_asset.split("/"))
            if not is_path_within(pkg_dir, asset_full) or not os.path.isfile(asset_full) or os.path.islink(asset_full):
                raise ValueError(f"Required package asset missing in slot: {rel_asset}")

    if verify_tree_hash:
        actual_tree_sha, _ = compute_package_tree_sha256(pkg_dir)
        if actual_tree_sha != tree_sha.lower():
            raise ValueError("Overlay slot file integrity digest mismatch.")

    return slot_dir, slot_meta


def default_manifest(bundled_version=""):
    return {
        "schema_version": SCHEMA_VERSION,
        "bundled_version": bundled_version or "",
        "active_slot": None,
        "active_version": None,
        "active_sha256": None,
        "previous_slot": None,
        "previous_version": None,
        "previous_sha256": None,
        "pending_slot": None,
        "pending_version": None,
        "pending_sha256": None,
        "pending_source_url": None,
        "last_known_good_slot": None,
        "last_known_good_version": None,
        "failed_slots": [],
        "transaction": {
            "id": None,
            "state": "idle",
            "started_at": None,
            "updated_at": None,
            "target_version": None,
        },
        "recovery_required": False,
        "last_error": None,
        "rolled_back_from": None,
    }


def sanitize_manifest(raw, bundled_version=""):
    if not isinstance(raw, dict):
        raise ValueError("Manifest root must be a JSON object.")
    schema = raw.get("schema_version")
    if schema != SCHEMA_VERSION:
        raise ValueError(f"Unsupported overlay manifest schema: {schema}")

    base = default_manifest(bundled_version or str(raw.get("bundled_version") or ""))
    for key in (
        "active_slot",
        "active_version",
        "active_sha256",
        "previous_slot",
        "previous_version",
        "previous_sha256",
        "pending_slot",
        "pending_version",
        "pending_sha256",
        "pending_source_url",
        "last_known_good_slot",
        "last_known_good_version",
        "last_error",
        "rolled_back_from",
    ):
        val = raw.get(key)
        if val is not None and not isinstance(val, str):
            raise ValueError(f"Manifest field {key} must be string or null.")
        base[key] = val

    for slot_key in ("active_slot", "previous_slot", "pending_slot", "last_known_good_slot"):
        val = base[slot_key]
        if val is not None and not _SLOT_NAME_RE.match(val):
            raise ValueError(f"Manifest contains unsafe slot identifier in {slot_key}.")

    failed = raw.get("failed_slots", [])
    if not isinstance(failed, list) or not all(isinstance(item, str) for item in failed):
        raise ValueError("Manifest failed_slots must be a list of strings.")
    base["failed_slots"] = failed[-16:]

    tx = raw.get("transaction")
    if tx is not None:
        if not isinstance(tx, dict):
            raise ValueError("Manifest transaction must be an object.")
        base["transaction"] = {
            "id": tx.get("id") if isinstance(tx.get("id"), str) else None,
            "state": str(tx.get("state") or "idle"),
            "started_at": tx.get("started_at"),
            "updated_at": tx.get("updated_at"),
            "target_version": tx.get("target_version") if isinstance(tx.get("target_version"), str) else None,
        }

    base["recovery_required"] = bool(raw.get("recovery_required", False))
    if bundled_version:
        base["bundled_version"] = bundled_version
    return base


def atomic_write_json(target_path, payload):
    parent = os.path.dirname(os.path.abspath(target_path))
    os.makedirs(parent, exist_ok=True)
    tmp_name = f".{os.path.basename(target_path)}.tmp.{os.getpid()}.{threading.get_ident()}"
    tmp_path = os.path.join(parent, tmp_name)
    encoded = json.dumps(payload, indent=2, sort_keys=True)
    with open(tmp_path, "w", encoding="utf-8") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_path, target_path)
    try:
        dir_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass


def load_manifest(manifest_path, bundled_version=""):
    if not os.path.exists(manifest_path):
        return default_manifest(bundled_version), None
    if os.path.islink(manifest_path) or os.path.getsize(manifest_path) > _MAX_MANIFEST_BYTES:
        raise ValueError("Manifest is a symlink or exceeds safety limit.")
    with open(manifest_path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)
    return sanitize_manifest(raw, bundled_version), None


def _quarantine_corrupt_manifest(manifest_path):
    if not os.path.exists(manifest_path):
        return None
    corrupt_path = f"{manifest_path}.corrupt.{int(time.time())}"
    try:
        shutil.copyfile(manifest_path, corrupt_path)
    except OSError:
        corrupt_path = None
    return corrupt_path


def _extract_version_from_pyc_bytes(data):
    if not data or len(data) <= 16:
        return None
    for offset in (16, 12):
        try:
            code = marshal.loads(data[offset:])
            namespace = {"__builtins__": {}}
            exec(code, namespace, namespace)
            ver = namespace.get("__version__")
            if isinstance(ver, str) and parse_calver(ver):
                return normalize_calver(ver)
        except Exception:
            continue
    return None


def _read_bundled_version_non_importing(overlay_root):
    spec = importlib.util.find_spec("yt_dlp")
    if spec is None:
        return ""
    origin = getattr(spec, "origin", None) or ""
    if origin and is_path_within(overlay_root, origin):
        return ""
    loader = getattr(spec, "loader", None)
    if origin and loader is not None:
        parent = os.path.dirname(origin)
        get_data = getattr(loader, "get_data", None)
        if callable(get_data):
            for candidate_name in ("version.py", "version.pyc"):
                candidate_path = os.path.join(parent, candidate_name)
                try:
                    raw_bytes = get_data(candidate_path)
                except Exception:
                    raw_bytes = None
                if raw_bytes:
                    if candidate_name.endswith(".py"):
                        try:
                            parsed = extract_version_from_ast(raw_bytes.decode("utf-8"))
                            if parsed and parse_calver(parsed):
                                return normalize_calver(parsed)
                        except Exception:
                            pass
                    else:
                        parsed = _extract_version_from_pyc_bytes(raw_bytes)
                        if parsed:
                            return parsed
        archive_path = getattr(loader, "archive", None)
        if isinstance(archive_path, str) and os.path.isfile(archive_path):
            try:
                with zipfile.ZipFile(archive_path, "r") as zf:
                    for member in ("yt_dlp/version.py", "yt_dlp/version.pyc"):
                        if member in zf.namelist():
                            raw_bytes = zf.read(member)
                            if member.endswith(".py"):
                                parsed = extract_version_from_ast(raw_bytes.decode("utf-8"))
                                if parsed and parse_calver(parsed):
                                    return normalize_calver(parsed)
                            else:
                                parsed = _extract_version_from_pyc_bytes(raw_bytes)
                                if parsed:
                                    return parsed
            except Exception:
                pass
    return ""


def _purge_ytdlp_from_sys(slot_dir=None):
    if slot_dir:
        slot_real = os.path.realpath(os.path.abspath(slot_dir))
        sys.path[:] = [p for p in sys.path if os.path.realpath(os.path.abspath(p)) != slot_real]
    to_remove = [name for name in list(sys.modules.keys()) if name == "yt_dlp" or name.startswith("yt_dlp.")]
    for name in to_remove:
        sys.modules.pop(name, None)
    importlib.invalidate_caches()


def _smoke_test_ytdlp(expected_source, expected_slot_dir=None, expected_version=None):
    import yt_dlp
    import yt_dlp.version

    mod_file = getattr(yt_dlp, "__file__", None) or ""
    if not mod_file:
        raise RuntimeError("Imported yt_dlp module has no __file__ origin.")

    if expected_source == "overlay":
        if not expected_slot_dir:
            raise RuntimeError("Missing expected_slot_dir for overlay verification.")
        expected_pkg_root = os.path.realpath(os.path.join(expected_slot_dir, "yt_dlp"))
        mod_real = os.path.realpath(mod_file)
        if not is_path_within(expected_pkg_root, mod_real):
            raise RuntimeError(f"yt_dlp imported from {mod_real} instead of overlay {expected_pkg_root}.")

    live_version = normalize_calver(str(getattr(yt_dlp.version, "__version__", "") or ""))
    if not live_version:
        raise RuntimeError("Imported yt_dlp.version.__version__ is empty.")
    if expected_version and live_version != normalize_calver(expected_version):
        raise RuntimeError(f"Imported yt_dlp version {live_version} does not match expected {expected_version}.")

    ydl_cls = getattr(yt_dlp, "YoutubeDL", None)
    if ydl_cls is None:
        raise RuntimeError("Imported yt_dlp module does not expose YoutubeDL.")
    with ydl_cls({"quiet": True, "no_color": True, "noprogress": True}) as instance:
        if instance is None:
            raise RuntimeError("YoutubeDL instantiation returned None.")

    return live_version, os.path.realpath(mod_file)


def _strip_overlay_paths_from_sys_path(slots_dir):
    slots_real = os.path.realpath(os.path.abspath(slots_dir))
    sys.path[:] = [
        p for p in sys.path
        if not is_path_within(slots_real, p)
    ]


def _append_failed_slot(manifest, slot_id):
    if slot_id and slot_id not in manifest["failed_slots"]:
        manifest["failed_slots"] = (manifest["failed_slots"] + [slot_id])[-16:]


def _prune_superseded_slots(slots_dir, manifest):
    if not os.path.isdir(slots_dir):
        return
    keep = {
        manifest.get("active_slot"),
        manifest.get("previous_slot"),
        manifest.get("pending_slot"),
        manifest.get("last_known_good_slot"),
    }
    keep.discard(None)
    for entry in os.listdir(slots_dir):
        if entry in keep:
            continue
        candidate = os.path.join(slots_dir, entry)
        try:
            if os.path.isdir(candidate) and not os.path.islink(candidate):
                shutil.rmtree(candidate, ignore_errors=True)
        except OSError:
            pass


def _activate_slot(slots_dir, slot_id, expected_version, bundled_version):
    slot_dir, slot_meta = validate_slot_directory(
        slots_dir,
        slot_id,
        expected_version=expected_version,
        verify_tree_hash=True,
    )
    slot_ver = normalize_calver(str(slot_meta["version"]))
    if bundled_version and parse_calver(bundled_version) is not None:
        if parse_calver(slot_ver) < parse_calver(bundled_version):
            raise ValueError(f"Overlay slot {slot_ver} is older than bundled {bundled_version}.")
    _strip_overlay_paths_from_sys_path(slots_dir)
    sys.path.insert(0, slot_dir)
    importlib.invalidate_caches()
    live_ver, origin_file = _smoke_test_ytdlp(
        "overlay",
        expected_slot_dir=slot_dir,
        expected_version=slot_ver,
    )
    return slot_dir, live_ver, origin_file


def _record_bootstrap_state(
    paths,
    manifest,
    active_source,
    active_version,
    origin_file,
    bundled_version,
    premature_import=False,
    bootstrap_error=None,
    rolled_back=False,
):
    pending_ver = manifest.get("pending_version")
    pending_slot = manifest.get("pending_slot")
    return {
        "initialized": True,
        "overlay_root": paths["root"],
        "slots_dir": paths["slots"],
        "manifest_path": paths["manifest"],
        "bundled_version": bundled_version or manifest.get("bundled_version") or "",
        "active_source": active_source,
        "active_version": active_version or "",
        "active_slot": manifest.get("active_slot") if active_source == "overlay" else None,
        "previous_slot": manifest.get("previous_slot"),
        "previous_version": manifest.get("previous_version"),
        "pending_slot": pending_slot,
        "pending_version": pending_ver,
        "restart_required": bool(pending_slot and pending_ver),
        "recovery_required": bool(manifest.get("recovery_required", False)),
        "rolled_back": bool(rolled_back or manifest.get("rolled_back_from")),
        "rolled_back_from": manifest.get("rolled_back_from"),
        "last_error": bootstrap_error or manifest.get("last_error"),
        "premature_import": bool(premature_import),
        "origin_file": origin_file or "",
        "selected_path": os.path.dirname(origin_file) if origin_file else "",
        "transaction_state": str(manifest.get("transaction", {}).get("state") or "idle"),
    }


def bootstrap(overlay_root, bundled_version_hint=None):
    global _RUNTIME_STATE
    with _BOOTSTRAP_LOCK:
        paths = resolve_overlay_paths(overlay_root)
        if _RUNTIME_STATE is not None and _RUNTIME_STATE.get("overlay_root") == paths["root"]:
            return dict(_RUNTIME_STATE)

        hint_norm = normalize_calver(bundled_version_hint or "")
        if "yt_dlp" in sys.modules:
            existing_mod = sys.modules["yt_dlp"]
            existing_file = getattr(existing_mod, "__file__", "") or ""
            existing_ver = ""
            try:
                import yt_dlp.version
                existing_ver = normalize_calver(str(getattr(yt_dlp.version, "__version__", "") or ""))
            except Exception:
                existing_ver = ""
            source = "overlay" if existing_file and is_path_within(paths["slots"], existing_file) else "bundled"
            try:
                manifest, _ = load_manifest(paths["manifest"], hint_norm or existing_ver)
            except Exception:
                manifest = default_manifest(hint_norm or existing_ver)
            err = "yt_dlp was already imported before overlay_bootstrap.bootstrap() ran; refusing in-process swap."
            _RUNTIME_STATE = _record_bootstrap_state(
                paths,
                manifest,
                active_source=source,
                active_version=existing_ver,
                origin_file=existing_file,
                bundled_version=hint_norm or (existing_ver if source == "bundled" else manifest.get("bundled_version", "")),
                premature_import=True,
                bootstrap_error=err,
            )
            return dict(_RUNTIME_STATE)

        inspected_bundled = _read_bundled_version_non_importing(paths["root"])
        bundled_version = inspected_bundled or hint_norm
        if parse_calver(bundled_version) is None:
            bundled_version = hint_norm

        manifest_existed = os.path.exists(paths["manifest"])
        manifest_corrupted = False
        corrupt_backup = None
        if manifest_existed:
            try:
                manifest, _ = load_manifest(paths["manifest"], bundled_version)
            except Exception as exc:
                manifest_corrupted = True
                corrupt_backup = _quarantine_corrupt_manifest(paths["manifest"])
                manifest = default_manifest(bundled_version)
                manifest["last_error"] = (
                    f"Corrupted overlay manifest preserved ({os.path.basename(corrupt_backup) if corrupt_backup else 'quarantined'}); "
                    f"fell back to bundled yt_dlp: {exc}"
                )
        else:
            manifest = default_manifest(bundled_version)

        manifest_dirty = manifest_corrupted
        rolled_back = False

        tx = manifest["transaction"]
        pending_slot = manifest.get("pending_slot")
        pending_version = manifest.get("pending_version")

        if tx.get("state") == "activating" and pending_slot:
            _append_failed_slot(manifest, pending_slot)
            manifest["rolled_back_from"] = pending_version or pending_slot
            manifest["last_error"] = (
                f"Previous activation attempt for {pending_version or pending_slot} did not finish cleanly; rolled back."
            )
            manifest["pending_slot"] = None
            manifest["pending_version"] = None
            manifest["pending_sha256"] = None
            manifest["pending_source_url"] = None
            manifest["transaction"] = {
                "id": tx.get("id"),
                "state": "rolled_back",
                "started_at": tx.get("started_at"),
                "updated_at": int(time.time()),
                "target_version": pending_version,
            }
            manifest_dirty = True
            rolled_back = True
            pending_slot = None
            pending_version = None

        if pending_slot and tx.get("state") == "pending_activation":
            if bundled_version and parse_calver(bundled_version) and pending_version:
                if parse_calver(pending_version) < parse_calver(bundled_version):
                    _append_failed_slot(manifest, pending_slot)
                    manifest["rolled_back_from"] = pending_version
                    manifest["last_error"] = (
                        f"Pending overlay {pending_version} is older than bundled {bundled_version}; using bundled."
                    )
                    manifest["pending_slot"] = None
                    manifest["pending_version"] = None
                    manifest["pending_sha256"] = None
                    manifest["pending_source_url"] = None
                    manifest["transaction"]["state"] = "rolled_back"
                    manifest["transaction"]["updated_at"] = int(time.time())
                    manifest_dirty = True
                    rolled_back = True
                    pending_slot = None

        if pending_slot and manifest.get("transaction", {}).get("state") == "pending_activation":
            prior_active_slot = manifest.get("active_slot")
            prior_active_ver = manifest.get("active_version")
            prior_active_sha = manifest.get("active_sha256")
            pending_sha = manifest.get("pending_sha256")

            manifest["transaction"]["state"] = "activating"
            manifest["transaction"]["updated_at"] = int(time.time())
            atomic_write_json(paths["manifest"], manifest)

            try:
                slot_dir, live_ver, origin_file = _activate_slot(
                    paths["slots"],
                    pending_slot,
                    pending_version,
                    bundled_version,
                )
                if prior_active_slot and prior_active_slot != pending_slot:
                    manifest["previous_slot"] = prior_active_slot
                    manifest["previous_version"] = prior_active_ver
                    manifest["previous_sha256"] = prior_active_sha
                manifest["active_slot"] = pending_slot
                manifest["active_version"] = live_ver
                manifest["active_sha256"] = pending_sha
                manifest["last_known_good_slot"] = pending_slot
                manifest["last_known_good_version"] = live_ver
                manifest["pending_slot"] = None
                manifest["pending_version"] = None
                manifest["pending_sha256"] = None
                manifest["pending_source_url"] = None
                manifest["recovery_required"] = False
                manifest["last_error"] = None
                manifest["rolled_back_from"] = None
                manifest["transaction"] = {
                    "id": manifest["transaction"].get("id"),
                    "state": "idle",
                    "started_at": manifest["transaction"].get("started_at"),
                    "updated_at": int(time.time()),
                    "target_version": None,
                }
                atomic_write_json(paths["manifest"], manifest)
                _prune_superseded_slots(paths["slots"], manifest)
                _RUNTIME_STATE = _record_bootstrap_state(
                    paths,
                    manifest,
                    active_source="overlay",
                    active_version=live_ver,
                    origin_file=origin_file,
                    bundled_version=bundled_version,
                )
                return dict(_RUNTIME_STATE)
            except Exception as exc:
                _purge_ytdlp_from_sys(os.path.join(paths["slots"], pending_slot))
                _append_failed_slot(manifest, pending_slot)
                manifest["rolled_back_from"] = pending_version or pending_slot
                manifest["last_error"] = f"Pending overlay {pending_version or pending_slot} failed verification ({exc}); rolled back."
                manifest["pending_slot"] = None
                manifest["pending_version"] = None
                manifest["pending_sha256"] = None
                manifest["pending_source_url"] = None
                manifest["transaction"]["state"] = "rolled_back"
                manifest["transaction"]["updated_at"] = int(time.time())
                manifest_dirty = True
                rolled_back = True

        candidate_chain = []
        if manifest.get("active_slot"):
            candidate_chain.append(("active", manifest.get("active_slot"), manifest.get("active_version"), manifest.get("active_sha256")))
        if manifest.get("previous_slot") and manifest.get("previous_slot") != manifest.get("active_slot"):
            candidate_chain.append(("previous", manifest.get("previous_slot"), manifest.get("previous_version"), manifest.get("previous_sha256")))

        for role, slot_id, slot_ver, slot_sha in candidate_chain:
            if bundled_version and parse_calver(bundled_version) and slot_ver and parse_calver(slot_ver):
                if parse_calver(slot_ver) < parse_calver(bundled_version):
                    manifest["last_error"] = (
                        f"Bundled APK yt_dlp ({bundled_version}) supersedes older overlay ({slot_ver}); using bundled."
                    )
                    manifest["active_slot"] = None
                    manifest["active_version"] = None
                    manifest["active_sha256"] = None
                    manifest_dirty = True
                    continue
            try:
                slot_dir, live_ver, origin_file = _activate_slot(
                    paths["slots"],
                    slot_id,
                    slot_ver,
                    bundled_version,
                )
                if role == "previous":
                    manifest["active_slot"] = slot_id
                    manifest["active_version"] = live_ver
                    manifest["active_sha256"] = slot_sha
                    manifest["last_known_good_slot"] = slot_id
                    manifest["last_known_good_version"] = live_ver
                    manifest["transaction"]["state"] = "rolled_back"
                    manifest["transaction"]["updated_at"] = int(time.time())
                    manifest_dirty = True
                if manifest_dirty:
                    atomic_write_json(paths["manifest"], manifest)
                _prune_superseded_slots(paths["slots"], manifest)
                _RUNTIME_STATE = _record_bootstrap_state(
                    paths,
                    manifest,
                    active_source="overlay",
                    active_version=live_ver,
                    origin_file=origin_file,
                    bundled_version=bundled_version,
                    rolled_back=rolled_back,
                )
                return dict(_RUNTIME_STATE)
            except Exception as exc:
                _purge_ytdlp_from_sys(os.path.join(paths["slots"], slot_id))
                _append_failed_slot(manifest, slot_id)
                if manifest.get("active_slot") == slot_id:
                    manifest["active_slot"] = None
                    manifest["active_version"] = None
                    manifest["active_sha256"] = None
                if manifest.get("previous_slot") == slot_id:
                    manifest["previous_slot"] = None
                    manifest["previous_version"] = None
                    manifest["previous_sha256"] = None
                manifest["rolled_back_from"] = manifest.get("rolled_back_from") or slot_ver or slot_id
                manifest["last_error"] = f"Overlay slot {slot_id} failed validation ({exc}); falling back."
                manifest["transaction"]["state"] = "rolled_back"
                manifest["transaction"]["updated_at"] = int(time.time())
                manifest_dirty = True
                rolled_back = True

        _strip_overlay_paths_from_sys_path(paths["slots"])
        _purge_ytdlp_from_sys()
        try:
            live_ver, origin_file = _smoke_test_ytdlp("bundled")
            bundled_version = bundled_version or live_ver
            manifest["bundled_version"] = bundled_version
            manifest["recovery_required"] = False
            if manifest_dirty:
                atomic_write_json(paths["manifest"], manifest)
            _RUNTIME_STATE = _record_bootstrap_state(
                paths,
                manifest,
                active_source="bundled",
                active_version=live_ver,
                origin_file=origin_file,
                bundled_version=bundled_version,
                rolled_back=rolled_back,
            )
            return dict(_RUNTIME_STATE)
        except Exception as exc:
            manifest["recovery_required"] = True
            manifest["last_error"] = f"Critical error: neither overlay nor bundled yt_dlp loaded ({exc})."
            try:
                atomic_write_json(paths["manifest"], manifest)
            except OSError:
                pass
            _RUNTIME_STATE = _record_bootstrap_state(
                paths,
                manifest,
                active_source="unavailable",
                active_version="",
                origin_file="",
                bundled_version=bundled_version,
                bootstrap_error=manifest["last_error"],
                rolled_back=rolled_back,
            )
            return dict(_RUNTIME_STATE)


def get_runtime_status(overlay_root=None):
    with _BOOTSTRAP_LOCK:
        if _RUNTIME_STATE is not None:
            state = dict(_RUNTIME_STATE)
            if overlay_root:
                paths = resolve_overlay_paths(overlay_root)
                try:
                    manifest, _ = load_manifest(paths["manifest"], state.get("bundled_version", ""))
                    state["pending_slot"] = manifest.get("pending_slot")
                    state["pending_version"] = manifest.get("pending_version")
                    state["restart_required"] = bool(manifest.get("pending_slot") and manifest.get("pending_version"))
                    state["recovery_required"] = bool(manifest.get("recovery_required", False))
                    state["transaction_state"] = str(manifest.get("transaction", {}).get("state") or "idle")
                    if manifest.get("last_error"):
                        state["last_error"] = manifest.get("last_error")
                    if manifest.get("rolled_back_from"):
                        state["rolled_back"] = True
                        state["rolled_back_from"] = manifest.get("rolled_back_from")
                except Exception as exc:
                    state["recovery_required"] = True
                    state["last_error"] = f"Overlay manifest unreadable: {exc}"
            return state
        return {
            "initialized": False,
            "overlay_root": overlay_root or "",
            "bundled_version": "",
            "active_source": "uninitialized",
            "active_version": "",
            "active_slot": None,
            "previous_slot": None,
            "previous_version": None,
            "pending_slot": None,
            "pending_version": None,
            "restart_required": False,
            "recovery_required": False,
            "rolled_back": False,
            "rolled_back_from": None,
            "last_error": None,
            "premature_import": False,
            "origin_file": "",
            "selected_path": "",
            "transaction_state": "idle",
        }


def reset_runtime_state_for_tests():
    global _RUNTIME_STATE
    with _BOOTSTRAP_LOCK:
        _RUNTIME_STATE = None
