# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import yt_dlp
import json
import os
import urllib.request

active_jobs = {}

USER_AGENT = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"


def _best_thumbnail(info):
    thumbs = info.get("thumbnails") or []
    ranked = sorted(
        [t for t in thumbs if t.get("url")],
        key=lambda t: (t.get("preference") or 0, (t.get("width") or 0) * (t.get("height") or 0)),
        reverse=True,
    )
    if ranked:
        return ranked[0]["url"]
    return info.get("thumbnail") or ""


def _info_block(info):
    if not info:
        return {}
    artists = info.get("artists") or []
    artist = info.get("artist") or (", ".join(artists) if artists else "") or info.get("creator") or ""
    upload = info.get("upload_date") or ""
    return {
        "id": info.get("id", ""),
        "title": info.get("title", ""),
        "track": info.get("track") or "",
        "artist": artist,
        "album": info.get("album") or "",
        "album_artist": info.get("album_artist") or "",
        "track_number": str(info.get("track_number") or ""),
        "release_year": str(info.get("release_year") or (upload[:4] if upload else "")),
        "genre": (info.get("genres") or [info.get("genre") or ""])[0] if (info.get("genres") or info.get("genre")) else "",
        "uploader": info.get("uploader") or "",
        "channel": info.get("channel") or info.get("uploader") or "",
        "duration": info.get("duration") or 0,
        "thumbnail": _best_thumbnail(info),
        "webpage_url": info.get("webpage_url") or info.get("original_url") or "",
        "extractor": info.get("extractor_key") or info.get("extractor") or "",
    }


def _base_opts():
    return {"quiet": True, "no_warnings": True, "noprogress": True}


def search_media(query, source, limit=15):
    try:
        opts = _base_opts()
        opts["extract_flat"] = True
        if source == "soundcloud":
            target = f"scsearch{limit}:{query}"
        else:
            target = f"ytsearch{limit}:{query}"
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(target, download=False)
            results = []
            for e in (info.get("entries") or [])[:limit]:
                if not e:
                    continue
                url = e.get("url") or e.get("webpage_url") or ""
                if url and not url.startswith("http") and e.get("id") and source != "soundcloud":
                    url = f"https://www.youtube.com/watch?v={e['id']}"
                results.append({
                    "title": e.get("title") or "Unknown",
                    "uploader": e.get("uploader") or e.get("channel") or ", ".join(e.get("artists") or []) or "Unknown",
                    "duration": int(e.get("duration") or 0),
                    "url": url,
                    "thumbnail": _best_thumbnail(e),
                })
            return json.dumps({"status": "success", "results": results})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})


def get_available_formats(url):
    try:
        opts = _base_opts()
        opts["extract_flat"] = "in_playlist"
        opts["noplaylist"] = True
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)

            if info.get("_type") == "playlist" or "entries" in info:
                entries = [e for e in (info.get("entries") or []) if e]
                return json.dumps({
                    "status": "success",
                    "is_playlist": True,
                    "title": info.get("title", "Unknown Playlist"),
                    "track_count": len(entries),
                    "formats": [],
                })

            parsed_formats = []
            for f in info.get("formats", []):
                parsed_formats.append({
                    "format_id": f.get("format_id"),
                    "ext": f.get("ext"),
                    "resolution": f.get("resolution", "audio only" if f.get("vcodec") == "none" else "unknown"),
                    "filesize": f.get("filesize") or f.get("filesize_approx"),
                    "vcodec": f.get("vcodec"),
                    "acodec": f.get("acodec"),
                    "abr": f.get("abr"),
                    "vbr": f.get("vbr"),
                    "format_note": f.get("format_note", ""),
                })

            return json.dumps({
                "status": "success",
                "is_playlist": False,
                "title": info.get("title", "Unknown Title"),
                "info": _info_block(info),
                "formats": parsed_formats,
            })
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})


def cancel(job_id):
    if job_id in active_jobs:
        active_jobs[job_id] = False
        return json.dumps({"status": "success", "jobId": job_id})
    return json.dumps({"status": "error", "message": "No active job", "jobId": job_id})


def fetch_thumbnail(url, out_path):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read(10 * 1024 * 1024)
        if len(data) < 256:
            raise ValueError("Thumbnail payload too small")
        with open(out_path, "wb") as fh:
            fh.write(data)
        return json.dumps({"status": "success", "path": out_path})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})


def _requested_path(ydl, info):
    req = info.get("requested_downloads") or []
    if req and req[0].get("filepath"):
        return req[0]["filepath"]
    return ydl.prepare_filename(info)


def download(url, options_json, job_id, out_dir, progress_callback):
    try:
        active_jobs[job_id] = True
        options = json.loads(options_json)
        format_id = options.get("formatId", "best")
        allow_playlist = bool(options.get("playlist", False))

        def create_hook(label):
            def hook(d):
                if not active_jobs.get(job_id, False):
                    raise Exception("CANCELLED_BY_USER")
                if d["status"] == "downloading":
                    total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                    downloaded = d.get("downloaded_bytes", 0)
                    percent = (downloaded / total) if total > 0 else 0
                    filename = d.get("filename", "")
                    info = d.get("info_dict") or {}
                    payload = {
                        "jobId": job_id,
                        "status": "downloading",
                        "stage": label,
                        "percent": percent,
                        "speed": d.get("speed") or 0,
                        "eta": d.get("eta") or 0,
                        "current_file": info.get("title") or (os.path.basename(filename) if filename else ""),
                        "playlist_index": info.get("playlist_index") or 0,
                        "playlist_count": info.get("n_entries") or info.get("playlist_count") or 0,
                    }
                    progress_callback.invoke(json.dumps(payload))
            return hook

        def opts(fmt, template, label):
            o = _base_opts()
            o.update({
                "format": fmt,
                "outtmpl": os.path.join(out_dir, template),
                "progress_hooks": [create_hook(label)],
                "noplaylist": not allow_playlist,
            })
            return o

        if "+" in format_id:
            vid_fmt, aud_fmt = format_id.split("+", 1)
            with yt_dlp.YoutubeDL(opts(vid_fmt, f"{job_id}_v.%(ext)s", "video")) as ydl:
                info_v = ydl.extract_info(url, download=True)
                video_file = _requested_path(ydl, info_v)
            try:
                with yt_dlp.YoutubeDL(opts(aud_fmt, f"{job_id}_a.%(ext)s", "audio")) as ydl:
                    info_a = ydl.extract_info(url, download=True)
                    audio_file = _requested_path(ydl, info_a)
            except Exception:
                if video_file and os.path.exists(video_file):
                    try:
                        os.remove(video_file)
                    except Exception:
                        pass
                raise
            progress_callback.invoke(json.dumps({
                "jobId": job_id,
                "status": "finished",
                "filePath": video_file,
                "audioPath": audio_file,
                "isSplit": True,
                "isPlaylist": False,
                "info": _info_block(info_v),
            }))
        else:
            template = f"{job_id}_%(playlist_index|0)s_%(id)s.%(ext)s" if allow_playlist else f"{job_id}.%(ext)s"
            with yt_dlp.YoutubeDL(opts(format_id, template, "single")) as ydl:
                info = ydl.extract_info(url, download=True)
                entries = [e for e in (info.get("entries") or []) if e] if (info.get("_type") == "playlist" or "entries" in info) else None
                if entries is not None:
                    items = []
                    for e in entries:
                        try:
                            path = _requested_path(ydl, e)
                        except Exception:
                            path = ""
                        if path and os.path.exists(path):
                            items.append({"filePath": path, "info": _info_block(e)})
                    progress_callback.invoke(json.dumps({
                        "jobId": job_id,
                        "status": "finished",
                        "filePath": out_dir,
                        "items": items,
                        "isSplit": False,
                        "isPlaylist": True,
                        "info": {"title": info.get("title", "")},
                    }))
                else:
                    progress_callback.invoke(json.dumps({
                        "jobId": job_id,
                        "status": "finished",
                        "filePath": _requested_path(ydl, info),
                        "isSplit": False,
                        "isPlaylist": False,
                        "info": _info_block(info),
                    }))

        active_jobs.pop(job_id, None)
        return json.dumps({"status": "success", "jobId": job_id})

    except Exception as e:
        cancelled = active_jobs.get(job_id) is False or "CANCELLED_BY_USER" in str(e)
        active_jobs.pop(job_id, None)
        if cancelled:
            for name in os.listdir(out_dir):
                if name.startswith(job_id):
                    try:
                        os.remove(os.path.join(out_dir, name))
                    except Exception:
                        pass
            return json.dumps({"status": "cancelled", "jobId": job_id})
        return json.dumps({"status": "error", "message": str(e), "jobId": job_id})
