# updater.py

# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import os
import sys
import shutil
import json
import urllib.request
import tarfile
import tempfile

def execute_scorched_earth():
    try:
        updater_dir = os.path.dirname(os.path.abspath(__file__))
        override_ytdlp_path = os.path.join(updater_dir, "yt_dlp")
        
        try:
            import yt_dlp
            current_ytdlp_path = os.path.dirname(yt_dlp.__file__)
            if os.path.isdir(current_ytdlp_path) and ".zip" not in current_ytdlp_path:
                target_dir = current_ytdlp_path
            else:
                target_dir = override_ytdlp_path
        except ImportError:
            target_dir = override_ytdlp_path

        req = urllib.request.Request(
            "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest",
            headers={'User-Agent': 'Mozilla/5.0 (Android) SovereignTagger/1.0'}
        )
        
        with urllib.request.urlopen(req) as response:
            release_data = json.loads(response.read().decode('utf-8'))
        
        tarball_url = release_data.get("tarball_url")
        tag_name = release_data.get("tag_name", "Unknown")
        
        if not tarball_url:
            raise Exception("Critical: Tarball URL missing from GitHub API response.")

        temp_dir = tempfile.mkdtemp()
        tar_path = os.path.join(temp_dir, "latest_ytdlp.tar.gz")
        
        download_req = urllib.request.Request(
            tarball_url, 
            headers={'User-Agent': 'Mozilla/5.0 (Android) SovereignTagger/1.0'}
        )
        
        with urllib.request.urlopen(download_req) as response, open(tar_path, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)

        extract_path = os.path.join(temp_dir, "extracted")
        os.makedirs(extract_path, exist_ok=True)
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=extract_path)

        extracted_items = os.listdir(extract_path)
        if not extracted_items:
            raise Exception("Archive extraction failed: empty directory.")
        
        extracted_root = extracted_items[0]
        source_ytdlp_dir = os.path.join(extract_path, extracted_root, "yt_dlp")
        
        if not os.path.exists(source_ytdlp_dir):
            raise Exception("Critical: Extracted payload does not contain yt_dlp directory.")

        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)

        shutil.copytree(source_ytdlp_dir, target_dir)

        shutil.rmtree(temp_dir)

        keys_to_remove = [k for k in sys.modules if k.startswith('yt_dlp')]
        for k in keys_to_remove:
            del sys.modules[k]

        return json.dumps({
            "status": "success", 
            "message": f"Scorched Earth Complete. Core updated to {tag_name}."
        })

    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})

def update_python_stack():
    try:
        results = {}
        # Attempt pip upgrade for pure-python deps (best-effort; offline hosts will report error, not crash)
        for pkg in ["mutagen", "lyricsgenius"]:
            try:
                import pip  # type: ignore
                rc = pip.main(["install", "--upgrade", "--quiet", pkg])
                results[pkg] = "upgraded" if rc == 0 else f"pip rc={rc}"
            except Exception as pip_e:
                # Chaquopy environment fallback: try ensurepip path
                try:
                    import subprocess
                    rc2 = subprocess.call([sys.executable, "-m", "pip", "install", "--upgrade", "--quiet", pkg])
                    results[pkg] = "upgraded via subprocess" if rc2 == 0 else f"subprocess rc={rc2}"
                except Exception as e2:
                    results[pkg] = f"skip: {pip_e} / {e2}"
        return json.dumps({"status": "success", "results": results})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})

def execute_full_scorched_earth():
    ytdlp_res = json.loads(execute_scorched_earth())
    if ytdlp_res.get("status") != "success":
        return json.dumps(ytdlp_res)
    deps_res = json.loads(update_python_stack())
    # Always surface yt-dlp tag; deps are best-effort
    msg = ytdlp_res.get("message", "")
    if deps_res.get("status") == "success":
        msg += f" | Deps: {deps_res.get('results')}"
    else:
        msg += f" | Deps warn: {deps_res.get('message')}"
    return json.dumps({"status": "success", "message": msg})