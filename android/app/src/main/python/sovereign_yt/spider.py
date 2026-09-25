# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import json
import base64
import urllib.request
import urllib.parse
import lyricsgenius
import yt_dlp
import re
import time

def scrape_metadata(artist_name, song_title, genius_token):
    if not song_title:
        return json.dumps({"status": "error", "message": "Title required."})
        
    raw_artist = artist_name if artist_name else ""
    raw_title = song_title
    
    if not raw_artist and re.search(r'\s+[-_·]\s+', raw_title):
        parts = re.split(r'\s+[-_·]\s+', raw_title, maxsplit=1)
        raw_artist = parts[0]
        raw_title = parts[1]
        
    noise_pattern = r'(?i)\[.*?\]|\(.*?(?:official|video|audio|lyrics?|hq|1080p|4k|live).*?\)'
    clean_title = re.sub(noise_pattern, '', raw_title).strip()
    clean_artist = re.sub(noise_pattern, '', raw_artist).strip()
    
    track_no = ""
    track_match = re.match(r'^(\d{1,2})\s*[-_·.]?\s*(.+)', clean_title)
    if track_match:
        track_no = str(int(track_match.group(1)))
        clean_title = track_match.group(2).strip()

    metadata = {
        "status": "success",
        "title": clean_title,
        "artist": clean_artist,
        "album": "",
        "year": "",
        "lyrics": "",
        "artwork_base64": "",
        "genre": "",      
        "track_no": track_no,
        "disc_no": ""
    }

    if genius_token:
        try:
            genius = lyricsgenius.Genius(genius_token, skip_non_songs=True, remove_section_headers=False)
            genius.verbose = False 
            song = genius.search_song(clean_title, clean_artist)
            
            if song:
                metadata["title"] = getattr(song, 'title', clean_title)
                metadata["artist"] = getattr(song, 'artist', clean_artist)
                metadata["lyrics"] = getattr(song, 'lyrics', "")
                
                raw_album = getattr(song, 'album', "")
                if raw_album and hasattr(raw_album, 'name'):
                    metadata["album"] = raw_album.name
                elif isinstance(raw_album, str):
                    metadata["album"] = raw_album

                art_url = getattr(song, 'song_art_image_url', "")
                if art_url:
                    try:
                        art_req = urllib.request.Request(art_url, headers={'User-Agent': 'Mozilla/5.0'})
                        with urllib.request.urlopen(art_req) as art_response:
                            art_bytes = art_response.read()
                            metadata["artwork_base64"] = base64.b64encode(art_bytes).decode('utf-8')
                    except Exception:
                        pass 
        except Exception:
            pass

    # LRCLIB lyrics fallback (free, no key required)
    if not metadata["lyrics"]:
        try:
            lrclib_artist = urllib.parse.quote(clean_artist)
            lrclib_title = urllib.parse.quote(clean_title)
            lrclib_url = f"https://lrclib.net/api/search?q={lrclib_artist}%20{lrclib_title}"
            lrclib_req = urllib.request.Request(lrclib_url, headers={'User-Agent': 'SovereignTagger/1.0'})
            
            with urllib.request.urlopen(lrclib_req) as lrclib_response:
                lrclib_data = json.loads(lrclib_response.read().decode())
                if lrclib_data and len(lrclib_data) > 0:
                    match = lrclib_data[0]
                    synced_lyrics = match.get('syncedLyrics', '')
                    plain_lyrics = match.get('plainLyrics', '')
                    if synced_lyrics:
                        metadata["lyrics"] = synced_lyrics
                    elif plain_lyrics:
                        metadata["lyrics"] = plain_lyrics
        except Exception:
            pass

    try:
        ydl_opts = {'quiet': True, 'extract_flat': True, 'extractor_args': {'generic': ['impersonate'], 'youtube': ['player_client=android,web']}}
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            query = f"scsearch1:{clean_artist} {clean_title}"
            sc_info = ydl.extract_info(query, download=False)
            
            if sc_info and 'entries' in sc_info and len(sc_info['entries']) > 0:
                track = sc_info['entries'][0]

                if not metadata["artwork_base64"] and track.get('thumbnails'):
                    thumbs = sorted(track['thumbnails'], key=lambda x: x.get('width', 0), reverse=True)
                    sc_art_url = thumbs[0].get('url', '')
                    if sc_art_url:
                        sc_art_url = sc_art_url.replace('-large.jpg', '-t500x500.jpg')
                        art_req = urllib.request.Request(sc_art_url, headers={'User-Agent': 'Mozilla/5.0'})
                        with urllib.request.urlopen(art_req) as art_response:
                            art_bytes = art_response.read()
                            metadata["artwork_base64"] = base64.b64encode(art_bytes).decode('utf-8')

                if not metadata["album"]:
                    metadata["album"] = track.get('uploader', '')
                
                if not metadata["genre"] and track.get('genre'):
                    metadata["genre"] = track.get('genre', '')
    except Exception:
        pass

    try:
        query = f"{clean_artist} {clean_title}"
        safe_query = urllib.parse.quote(query)
        itunes_url = f"https://itunes.apple.com/search?term={safe_query}&entity=song&limit=1"
        req = urllib.request.Request(itunes_url, headers={'User-Agent': 'Mozilla/5.0'})
        
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            if data['resultCount'] > 0:
                track = data['results'][0]
                if not metadata["album"]:
                    metadata["album"] = track.get('collectionName', '')
                if not metadata["genre"]:
                    metadata["genre"] = track.get('primaryGenreName', '')
                if not metadata["track_no"]:
                    metadata["track_no"] = str(track.get('trackNumber', ''))
                if not metadata["disc_no"]:
                    metadata["disc_no"] = str(track.get('discNumber', ''))
                
                raw_date = track.get('releaseDate', '')
                if raw_date and not metadata["year"]:
                    metadata["year"] = raw_date[:4]
    except Exception:
        pass

    try:
        mb_artist = urllib.parse.quote(clean_artist)
        mb_title = urllib.parse.quote(clean_title)
        mb_url = f"https://musicbrainz.org/ws/2/recording?query=recording:\"{mb_title}\" AND artist:\"{mb_artist}\"&fmt=json"
        mb_req = urllib.request.Request(mb_url, headers={'User-Agent': 'SovereignTagger/1.0'})
        
        with urllib.request.urlopen(mb_req) as mb_response:
            mb_data = json.loads(mb_response.read().decode())
            if mb_data.get('recordings') and len(mb_data['recordings']) > 0:
                rec = mb_data['recordings'][0]
                
                if not metadata["genre"]:
                    tags = rec.get('tags', [])
                    if tags:
                        sorted_tags = sorted(tags, key=lambda x: x.get('count', 0), reverse=True)
                        metadata["genre"] = sorted_tags[0].get('name', '').title()

                releases = rec.get('releases', [])
                if releases:
                    if not metadata["year"]:
                        date = releases[0].get('date', '')
                        if date:
                            metadata["year"] = date[:4]
                    if not metadata["album"]:
                        metadata["album"] = releases[0].get('title', '')
    except Exception:
        pass

    return json.dumps(metadata)