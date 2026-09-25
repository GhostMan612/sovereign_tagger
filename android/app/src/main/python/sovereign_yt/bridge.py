# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import yt_dlp
import json
import os

active_jobs = {}

def search_media(query, source, limit=15):
    try:
        prefix = f"scsearch{limit}:" if source == "soundcloud" else f"ytsearch{limit}:"
        ydl_opts = {
            'extract_flat': True,
            'quiet': True,
            'no_warnings': True,
            'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"{prefix}{query}", download=False)
            entries = info.get('entries', [])
            results = []
            for e in entries:
                results.append({
                    "title": e.get('title', 'Unknown'),
                    "uploader": e.get('uploader', 'Unknown'),
                    "duration": e.get('duration', 0),
                    "url": e.get('url', '')
                })
            return json.dumps({"status": "success", "results": results})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})

def get_available_formats(url):
    try:
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': 'in_playlist',
            'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            if 'entries' in info:
                entries = list(info['entries'])
                return json.dumps({
                    "status": "success",
                    "is_playlist": True,
                    "title": info.get('title', 'Unknown Playlist'),
                    "track_count": len(entries),
                    "formats": []
                })

            formats = info.get('formats', [])
            parsed_formats = []
            for f in formats:
                parsed_formats.append({
                    'format_id': f.get('format_id'),
                    'ext': f.get('ext'),
                    'resolution': f.get('resolution', 'audio only' if f.get('vcodec') == 'none' else 'unknown'),
                    'filesize': f.get('filesize'),
                    'vcodec': f.get('vcodec'),
                    'acodec': f.get('acodec'),
                    'abr': f.get('abr'),
                    'vbr': f.get('vbr'),
                    'format_note': f.get('format_note', '')
                })
                
            return json.dumps({
                "status": "success", 
                "is_playlist": False,
                "title": info.get('title', 'Unknown Title'),
                "formats": parsed_formats
            })
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})

def download(url, options_json, job_id, out_dir, progress_callback):
    try:
        active_jobs[job_id] = True
        options = json.loads(options_json)
        
        format_id = options.get('formatId', 'best')
        is_split = "+" in format_id
        
        def create_hook(label):
            def hook(d):
                if not active_jobs.get(job_id, False):
                    raise Exception("CANCELLED_BY_USER")
                if d['status'] == 'downloading':
                    total = d.get('total_bytes') or d.get('total_bytes_estimate', 1)
                    downloaded = d.get('downloaded_bytes', 0)
                    percent = (downloaded / total) if total > 1 else 0
                    
                    filename = d.get('filename', '')
                    clean_name = os.path.basename(filename) if filename else ''
                    
                    payload = {
                        "jobId": job_id,
                        "status": "downloading",
                        "percent": percent,
                        "speed": d.get('speed', 0),
                        "eta": d.get('eta', 0),
                        "current_file": clean_name
                    }
                    progress_callback.invoke(json.dumps(payload))
            return hook

        info_dict_test = yt_dlp.YoutubeDL({'quiet': True, 'extract_flat': 'in_playlist', 'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}}).extract_info(url, download=False)
        is_playlist = 'entries' in info_dict_test

        if is_playlist:
            ydl_opts = {
                'outtmpl': os.path.join(out_dir, '%(playlist_index)s_%(title)s.%(ext)s'),
                'restrictfilenames': True,
                'quiet': True,
                'no_warnings': True,
                'format': format_id,
                'yes_playlist': True,
                'progress_hooks': [create_hook('playlist')],
                'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([url])
            
            payload = {
                "jobId": job_id,
                "status": "finished",
                "filePath": out_dir,
                "isSplit": False,
                "isPlaylist": True
            }
            progress_callback.invoke(json.dumps(payload))
            
        else:
            if is_split:
                vid_fmt, aud_fmt = format_id.split("+")
                v_opts = {
                    'format': vid_fmt,
                    'outtmpl': os.path.join(out_dir, f'{job_id}_v.%(ext)s'),
                    'quiet': True,
                    'no_warnings': True,
                    'progress_hooks': [create_hook('video')],
                    'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
                }
                video_file = None
                try:
                    with yt_dlp.YoutubeDL(v_opts) as ydl:
                        info_dict_v = ydl.extract_info(url, download=True)
                        req_v = info_dict_v.get('requested_downloads')
                        video_file = req_v[0].get('filepath') if req_v else ydl.prepare_filename(info_dict_v)
                except Exception as ve:
                    raise ve

                audio_file = None
                try:
                    a_opts = {
                        'format': aud_fmt,
                        'outtmpl': os.path.join(out_dir, f'{job_id}_a.%(ext)s'),
                        'quiet': True,
                        'no_warnings': True,
                        'progress_hooks': [create_hook('audio')],
                        'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
                    }
                    with yt_dlp.YoutubeDL(a_opts) as ydl:
                        info_dict_a = ydl.extract_info(url, download=True)
                        req_a = info_dict_a.get('requested_downloads')
                        audio_file = req_a[0].get('filepath') if req_a else ydl.prepare_filename(info_dict_a)
                except Exception as ae:
                    if video_file and os.path.exists(video_file):
                        try: os.remove(video_file)
                        except: pass
                    raise ae

                payload = {
                    "jobId": job_id,
                    "status": "finished",
                    "filePath": video_file,
                    "audioPath": audio_file,
                    "isSplit": True,
                    "isPlaylist": False
                }
                progress_callback.invoke(json.dumps(payload))
                
            else:
                ydl_opts = {
                    'outtmpl': os.path.join(out_dir, f'{job_id}.%(ext)s'),
                    'quiet': True,
                    'no_warnings': True,
                    'format': format_id,
                    'progress_hooks': [create_hook('single')],
                    'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}
                }
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info_dict = ydl.extract_info(url, download=True)
                    req = info_dict.get('requested_downloads')
                    final_file = req[0].get('filepath') if req else ydl.prepare_filename(info_dict)
                    
                payload = {
                    "jobId": job_id,
                    "status": "finished",
                    "filePath": final_file,
                    "isSplit": False,
                    "isPlaylist": False
                }
                progress_callback.invoke(json.dumps(payload))

        if job_id in active_jobs:
            del active_jobs[job_id]
            
        return json.dumps({"status": "success", "jobId": job_id})
        
    except Exception as e:
        if job_id in active_jobs:
            del active_jobs[job_id]
            
        msg = str(e)
        if "CANCELLED_BY_USER" in msg:
            return json.dumps({"status": "cancelled", "jobId": job_id})
            
        return json.dumps({"status": "error", "message": msg})