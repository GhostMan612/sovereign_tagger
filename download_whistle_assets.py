# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import hashlib
import pathlib
import urllib.request
import sys

def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def download(url: str, dest: pathlib.Path, min_size: int = 1000000):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size >= min_size:
        print(f"[ALREADY EXISTS] {dest} ({dest.stat().st_size} bytes)")
        return
    print(f"[DOWNLOADING] {url} -> {dest} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "SovereignTagger/2.0"})
    with urllib.request.urlopen(req) as resp, open(dest, "wb") as out:
        total = 0
        while chunk := resp.read(65536):
            out.write(chunk)
            total += len(chunk)
    print(f"[DOWNLOADED] {dest} ({dest.stat().st_size} bytes)")

def main():
    root = pathlib.Path(__file__).resolve().parent

    # 1. libneedle.a for android-arm64
    needle_lib = root / "android" / "app" / "src" / "main" / "jniLibs" / "arm64-v8a" / "libneedle.a"
    needle_urls = [
        "https://huggingface.co/Cactus-Compute/needle3/resolve/main/android-arm64/libneedle.a",
        "https://huggingface.co/Cactus-Compute/needle2/resolve/main/android-arm64/libneedle.a",
    ]
    needle_downloaded = False
    for url in needle_urls:
        try:
            download(url, needle_lib, min_size=1000000)
            needle_downloaded = True
            break
        except Exception as e:
            print(f"[WARNING] Failed from {url}: {e}")
    
    if needle_lib.exists():
        size = needle_lib.stat().st_size
        sha = sha256_file(needle_lib)
        print(f"libneedle.a: size={size} sha256={sha}")
    else:
        print("[ERROR] Could not download libneedle.a")
        sys.exit(1)

    # 2. whistle.cact model weights
    whistle_model = root / "assets" / "models" / "whistle.cact"
    whistle_url = "https://huggingface.co/Cactus-Compute/whistle/resolve/main/whistle.cact"
    try:
        download(whistle_url, whistle_model, min_size=10000000)
        size = whistle_model.stat().st_size
        sha = sha256_file(whistle_model)
        print(f"whistle.cact: size={size} sha256={sha}")
    except Exception as e:
        print(f"[ERROR] Failed to download whistle.cact: {e}")
        sys.exit(1)

    print("ALL WHISTLE ASSETS READY.")

if __name__ == "__main__":
    main()
