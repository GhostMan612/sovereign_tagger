# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import json
import os
import re

# Explicit knowledge base — patterns seen when YouTube/Google harden anti-bot
PATCH_REGISTRY = {
    "youtube_android_blocked": {
        "signature": ["Sign in to confirm you’re not a bot", "android.*player.*not available", "confirm you are not a bot"],
        "field": "youtube.player_client",
        "current": ["android"],
        "hotfix": ["android,web", "web", "ios"],
        "file": "bridge.py",
        "lines": "extractor_args youtube player_client"
    },
    "youtube_impersonate_removed": {
        "signature": ["impersonate.*unknown", "impersonate.*not supported", "generic.*impersonate"],
        "field": "generic.impersonate",
        "current": ["generic: impersonate"],
        "hotfix": [],
        "file": "bridge.py / spider.py",
        "lines": "extractor_args generic impersonate"
    },
    "youtube_403_throttle": {
        "signature": ["HTTP Error 403", "429", "Too Many Requests", "throttled"],
        "field": "youtube.throttle",
        "current": [],
        "hotfix": ["sleep 2s between extract_info calls", "rotate User-Agent SovereignTagger/1.x"],
        "file": "bridge.py download()",
        "lines": "progress_callback + extract_info throttling"
    },
    "spider_genius_429": {
        "signature": ["genius.*429", "genius.*rate limit", "search_song.*NoneType"],
        "field": "lyricsgenius",
        "current": ["skip_non_songs=True"],
        "hotfix": ["add retries=2, sleep_interval=1.0 to Genius()"],
        "file": "spider.py scrape_metadata()",
        "lines": "Genius init"
    },
    "ytdlp_outdated_extractor": {
        "signature": ["ExtractorError", "Unsupported URL", "Unable to extract", "yt-dlp.*outdated"],
        "field": "yt-dlp version",
        "current": ["pip 3.14 yt-dlp"],
        "hotfix": ["execute_scorched_earth() from updater.py – wipes yt_dlp folder + pulls latest tarball from GitHub"],
        "file": "updater.py",
        "lines": "execute_scorched_earth()"
    },
}

def diagnose(error_log: str = ""):
    try:
        error_log = error_log or ""
        lower = error_log.lower()
        hits = []
        for patch_id, info in PATCH_REGISTRY.items():
            for sig in info["signature"]:
                try:
                    if re.search(sig.lower(), lower):
                        hits.append({
                            "patch_id": patch_id,
                            "field": info["field"],
                            "file": info["file"],
                            "hotfix": info["hotfix"],
                        })
                        break
                except Exception:
                    if sig.lower() in lower:
                        hits.append({"patch_id": patch_id, "field": info["field"], "file": info["file"], "hotfix": info["hotfix"]})
                        break
        # Always include inventory of python payload
        py_dir = os.path.dirname(os.path.abspath(__file__))
        inventory = []
        for root, _, files in os.walk(py_dir):
            for f in files:
                if f.endswith('.py'):
                    fp = os.path.join(root, f)
                    try:
                        sz = os.path.getsize(fp)
                        inventory.append({"file": os.path.relpath(fp, py_dir), "bytes": sz})
                    except Exception:
                        pass
        # yt-dlp version probe (best-effort, no crash if missing)
        ytdlp_version = "unknown"
        try:
            import yt_dlp
            ytdlp_version = getattr(yt_dlp, 'version', getattr(yt_dlp, '__version__', 'unknown'))
            if callable(ytdlp_version):
                ytdlp_version = ytdlp_version()
        except Exception:
            pass

        # Current extractor_args snapshot (from bridge.py source text)
        extractor_snapshot = ""
        try:
            bridge_path = os.path.join(py_dir, "bridge.py")
            with open(bridge_path, "r", encoding="utf-8") as fh:
                txt = fh.read()
                m = re.findall(r"extractor_args[^}]*\}", txt, flags=re.DOTALL)
                extractor_snapshot = "\n".join(m[:3])[:1200]
        except Exception:
            pass

        return json.dumps({
            "status": "success",
            "ytdlp_version": str(ytdlp_version),
            "hits": hits,
            "inventory": inventory,
            "extractor_snapshot": extractor_snapshot,
            "registry_size": len(PATCH_REGISTRY),
            "hint": "If hits empty and ytdlp outdated, run Scorched Earth. If hits non-empty, apply first hotfix manually or trigger updater hot-patch."
        })
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})


def get_registry():
    try:
        slim = {k: {"file": v["file"], "field": v["field"], "hotfix": v["hotfix"]} for k, v in PATCH_REGISTRY.items()}
        return json.dumps({"status": "success", "registry": slim})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})
