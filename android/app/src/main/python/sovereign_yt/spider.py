# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

import json
import base64
import re
import time
import difflib
import unicodedata
import urllib.request
import urllib.parse

USER_AGENT = "SovereignTagger/2.0 (https://github.com/GhostMan612/sovereign_tagger)"
TIMEOUT = 10
MAX_ART_BYTES = 8 * 1024 * 1024

_NOISE_WORDS = (
    r"official(?:\s+(?:music|lyric|lyrics|audio|hd|4k))?\s*(?:video|audio|visuali[sz]er|clip)?|"
    r"music\s+video|lyric\s+video|lyrics?\s+video|lyrics?|audio(?:\s+only)?|visuali[sz]er|"
    r"video\s+oficial|clip\s+officiel|hd|hq|4k|8k|1080p|720p|mv|m/v|explicit|clean|"
    r"full\s+song|with\s+lyrics|color\s+coded"
)
_BRACKET_NOISE = re.compile(r"\s*[\(\[\{](?:[^\)\]\}]*?\b(?:" + _NOISE_WORDS + r")\b[^\)\]\}]*?)[\)\]\}]", re.IGNORECASE)
_TRAILING_NOISE = re.compile(r"\s*(?:[-|/~•:]\s*)?\b(?:" + _NOISE_WORDS + r")\s*$", re.IGNORECASE)
_PIPE_TAIL = re.compile(r"\s+[|｜]\s+.*$")
_TRACK_PREFIX = re.compile(r"^\s*(\d{1,3})\s*(?:[-–—.)]\s+|\s+[-–—]\s+)")
_FEAT = re.compile(r"\s*[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]?", re.IGNORECASE)
_VERSION_SEARCH = re.compile(r"\s*[\(\[][^\)\]]*\b(?:remaster(?:ed)?|deluxe|bonus|version|edit|mono|stereo)\b[^\)\]]*[\)\]]", re.IGNORECASE)
_CHANNEL_SUFFIX = re.compile(r"\s*(?:-\s*topic|vevo|official(?:\s+channel)?|\(official\))\s*$", re.IGNORECASE)
_SPLIT = re.compile(r"\s+[-–—]\s+|\s+[-–—]|[-–—]\s+")


def _get(url, headers=None, timeout=TIMEOUT, limit=None):
    h = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(limit) if limit else resp.read()


def _get_json(url, timeout=TIMEOUT):
    return json.loads(_get(url, timeout=timeout).decode("utf-8"))


def clean_title(raw):
    t = (raw or "").strip()
    t = _PIPE_TAIL.sub("", t)
    prev = None
    while prev != t:
        prev = t
        t = _BRACKET_NOISE.sub("", t)
        t = _TRAILING_NOISE.sub("", t).strip()
    t = re.sub(r"\s{2,}", " ", t)
    return t.strip(" -–—|~•:").strip()


def clean_artist(raw):
    a = (raw or "").strip()
    prev = None
    while prev != a:
        prev = a
        a = _CHANNEL_SUFFIX.sub("", a).strip()
    return a


def strip_track_prefix(title):
    m = _TRACK_PREFIX.match(title or "")
    if not m:
        return title, ""
    rest = title[m.end():].strip()
    if not rest:
        return title, ""
    return rest, str(int(m.group(1)))


def split_artist_title(artist, title):
    a = clean_artist(artist)
    t = clean_title(title)
    t, track_no = strip_track_prefix(t)
    channel_like = (not a) or bool(re.search(r"vevo|topic|official|records|music|tv$", artist or "", re.IGNORECASE))
    parts = _SPLIT.split(t, maxsplit=1)
    if len(parts) == 2 and parts[0].strip() and parts[1].strip():
        left, right = parts[0].strip(), parts[1].strip()
        if channel_like or _norm(left) == _norm(a) or _norm(a) in _norm(left):
            a = left
            t = right
    return clean_artist(a), clean_title(t), track_no


def search_form(text):
    s = _FEAT.sub("", text or "")
    s = _VERSION_SEARCH.sub("", s)
    return re.sub(r"\s{2,}", " ", s).strip()


def _norm(text):
    s = unicodedata.normalize("NFKD", search_form(text or "")).encode("ascii", "ignore").decode("ascii").lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\bthe\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def similarity(a, b):
    na, nb = _norm(a), _norm(b)
    if not na or not nb:
        return 0.0
    if na == nb:
        return 1.0
    ratio = difflib.SequenceMatcher(None, na, nb).ratio()
    ta, tb = set(na.split()), set(nb.split())
    small, big = (ta, tb) if len(ta) <= len(tb) else (tb, ta)
    containment = len(small & big) / len(small) if small else 0.0
    if containment == 1.0:
        containment = 0.92 + 0.08 * (len(small) / max(len(big), 1))
    return max(ratio, containment * 0.97)


def _duration_score(query_ms, cand_ms):
    if not query_ms or not cand_ms:
        return None
    diff = abs(query_ms - cand_ms) / 1000.0
    if diff <= 2:
        return 1.0
    if diff >= 20:
        return 0.0
    return 1.0 - (diff - 2) / 18.0


_VERSION_WORDS = ("live", "remix", "acoustic", "instrumental", "karaoke", "cover", "demo", "sped", "slowed", "nightcore", "reverb", "mix", "unplugged", "orchestral", "piano")
_ALBUM_WORDS = {"soundtrack": 0.05, "karaoke": 0.08, "tribute": 0.06, "hits": 0.03, "greatest": 0.03, "collection": 0.02, "compilation": 0.04, "live": 0.04, "anniversary": 0.01, "deluxe": 0.005, "edition": 0.005, "various": 0.05}


def _version_penalty(cand, title):
    wanted = set(_norm(title).split())
    got = set(_norm(cand.get("title", "")).split())
    penalty = 0.0
    for w in _VERSION_WORDS:
        if w in got and w not in wanted:
            penalty += 0.08
    album = set(_norm(cand.get("album", "")).split())
    for w, p in _ALBUM_WORDS.items():
        if w in album and w not in wanted:
            penalty += p
    return min(penalty, 0.3)


def score_candidate(cand, artist, title, duration_ms):
    parts = [(0.5, similarity(cand.get("search_title") or cand.get("title", ""), title) - _version_penalty(cand, title))]
    if artist:
        parts.append((0.35, similarity(cand.get("artist", ""), artist)))
    d = _duration_score(duration_ms, cand.get("duration_ms", 0))
    if d is not None:
        parts.append((0.15, d))
    total = sum(w for w, _ in parts)
    return round(sum(w * v for w, v in parts) / total, 4) if total else 0.0


def _itunes(artist, title):
    term = urllib.parse.quote(f"{artist} {title}".strip())
    data = _get_json(f"https://itunes.apple.com/search?term={term}&entity=song&limit=10")
    out = []
    for r in data.get("results", []):
        if r.get("kind") != "song":
            continue
        art = r.get("artworkUrl100", "")
        out.append({
            "source": "itunes",
            "id": str(r.get("trackId", "")),
            "title": r.get("trackName", ""),
            "search_title": r.get("trackCensoredName") or r.get("trackName", ""),
            "artist": r.get("artistName", ""),
            "album": r.get("collectionName", ""),
            "album_artist": r.get("collectionArtistName") or r.get("artistName", ""),
            "year": (r.get("releaseDate") or "")[:4],
            "genre": r.get("primaryGenreName", ""),
            "track_no": str(r.get("trackNumber") or ""),
            "track_total": str(r.get("trackCount") or ""),
            "disc_no": str(r.get("discNumber") or ""),
            "disc_total": str(r.get("discCount") or ""),
            "duration_ms": int(r.get("trackTimeMillis") or 0),
            "artwork_url": art.replace("100x100bb", "1200x1200bb") if art else "",
            "isrc": "",
        })
    return out


def _deezer(artist, title):
    q = urllib.parse.quote(f"{artist} {title}".strip())
    data = _get_json(f"https://api.deezer.com/search?q={q}&limit=10")
    out = []
    for r in data.get("data", []):
        album = r.get("album") or {}
        out.append({
            "source": "deezer",
            "id": str(r.get("id", "")),
            "title": r.get("title", ""),
            "search_title": r.get("title_short") or r.get("title", ""),
            "artist": (r.get("artist") or {}).get("name", ""),
            "album": album.get("title", ""),
            "album_artist": (r.get("artist") or {}).get("name", ""),
            "album_id": str(album.get("id", "")),
            "year": "",
            "genre": "",
            "track_no": "",
            "track_total": "",
            "disc_no": "",
            "disc_total": "",
            "duration_ms": int(r.get("duration") or 0) * 1000,
            "artwork_url": album.get("cover_xl") or album.get("cover_big") or "",
            "isrc": r.get("isrc", ""),
        })
    return out


def _deezer_details(cand):
    try:
        t = _get_json(f"https://api.deezer.com/track/{cand['id']}")
        cand["track_no"] = str(t.get("track_position") or cand.get("track_no") or "")
        cand["disc_no"] = str(t.get("disk_number") or cand.get("disc_no") or "")
        cand["year"] = (t.get("release_date") or "")[:4] or cand.get("year", "")
        cand["isrc"] = t.get("isrc") or cand.get("isrc", "")
        album = t.get("album") or {}
        if album.get("title"):
            cand["album"] = album["title"]
        album_id = album.get("id") or cand.get("album_id")
        if album_id:
            a = _get_json(f"https://api.deezer.com/album/{album_id}")
            genres = ((a.get("genres") or {}).get("data")) or []
            if genres:
                cand["genre"] = genres[0].get("name", "")
            if a.get("nb_tracks"):
                cand["track_total"] = str(a["nb_tracks"])
            artist = (a.get("artist") or {}).get("name")
            if artist:
                cand["album_artist"] = artist
            if not cand["year"]:
                cand["year"] = (a.get("release_date") or "")[:4]
    except Exception:
        pass
    return cand


def _pick_release(releases):
    def rank(r):
        rg = r.get("release-group") or {}
        secondary = rg.get("secondary-types") or []
        official = 0 if r.get("status") == "Official" else 1
        kind = {"Album": 0, "EP": 1, "Single": 2}.get(rg.get("primary-type"), 3)
        date = r.get("date") or "9999"
        return (official, 1 if secondary else 0, kind, date)
    return sorted(releases, key=rank)[0] if releases else None


def _musicbrainz(artist, title):
    query = f'recording:"{search_form(title)}"'
    if artist:
        query += f' AND artist:"{search_form(artist)}"'
    url = "https://musicbrainz.org/ws/2/recording?fmt=json&limit=8&query=" + urllib.parse.quote(query)
    data = _get_json(url)
    out = []
    for r in data.get("recordings", []):
        credit = r.get("artist-credit") or []
        artist_name = "".join((c.get("name", "") + c.get("joinphrase", "")) for c in credit).strip()
        rel = _pick_release(r.get("releases") or [])
        track_no = disc_no = track_total = ""
        album = album_artist = year = ""
        if rel:
            album = rel.get("title", "")
            rel_credit = rel.get("artist-credit") or credit
            album_artist = "".join((c.get("name", "") + c.get("joinphrase", "")) for c in rel_credit).strip()
            year = (rel.get("date") or "")[:4]
            media = rel.get("media") or []
            if media:
                m = media[0]
                disc_no = str(m.get("position") or "")
                track_total = str(m.get("track-count") or "")
                tracks = m.get("track") or []
                if tracks:
                    track_no = str(tracks[0].get("number") or "")
        first = (r.get("first-release-date") or "")[:4]
        out.append({
            "source": "musicbrainz",
            "id": r.get("id", ""),
            "title": r.get("title", ""),
            "search_title": r.get("title", ""),
            "artist": artist_name,
            "album": album,
            "album_artist": album_artist,
            "year": first or year,
            "genre": "",
            "track_no": track_no,
            "track_total": track_total,
            "disc_no": disc_no,
            "disc_total": "",
            "duration_ms": int(r.get("length") or 0),
            "artwork_url": f"https://coverartarchive.org/release/{rel['id']}/front-500" if rel and rel.get("id") else "",
            "isrc": "",
        })
    return out


def _lrclib_pick(items, artist, title, duration_ms):
    best, best_score = None, 0.0
    for it in items or []:
        if it.get("instrumental"):
            continue
        s = score_candidate({"title": it.get("trackName", ""), "artist": it.get("artistName", ""), "duration_ms": int(float(it.get("duration") or 0) * 1000)}, artist, title, duration_ms)
        if it.get("syncedLyrics"):
            s += 0.02
        if s > best_score:
            best, best_score = it, s
    return best if best_score >= 0.72 else None


def fetch_lyrics(artist, title, album="", duration_ms=0):
    a, t, _ = split_artist_title(artist, title)
    result = {"status": "success", "plain": "", "synced": "", "source": ""}
    hit = None
    try:
        params = {"artist_name": a, "track_name": search_form(t)}
        if album:
            params["album_name"] = album
        if duration_ms:
            params["duration"] = str(round(duration_ms / 1000))
        try:
            hit = _get_json("https://lrclib.net/api/get?" + urllib.parse.urlencode(params))
        except Exception:
            hit = None
        if not hit or not (hit.get("plainLyrics") or hit.get("syncedLyrics")):
            q = urllib.parse.urlencode({"track_name": search_form(t), "artist_name": a})
            hit = _lrclib_pick(_get_json("https://lrclib.net/api/search?" + q), a, t, duration_ms)
        if not hit:
            q = urllib.parse.urlencode({"q": f"{a} {search_form(t)}".strip()})
            hit = _lrclib_pick(_get_json("https://lrclib.net/api/search?" + q), a, t, duration_ms)
    except Exception:
        hit = None
    if hit:
        result["plain"] = (hit.get("plainLyrics") or "").strip()
        result["synced"] = (hit.get("syncedLyrics") or "").strip()
        result["source"] = "lrclib"
        if not result["plain"] and result["synced"]:
            result["plain"] = re.sub(r"^\s*\[[0-9:.]+\]\s*", "", result["synced"], flags=re.MULTILINE).strip()
    return json.dumps(result)


def _clean_genius(text):
    if not text:
        return ""
    t = text
    head = re.search(r"Lyrics(?=\[|\n|[A-Z])", t[:400])
    if head and ("Contributor" in t[:head.start()] or head.start() < 200):
        t = t[head.end():]
    t = re.sub(r"\d*\s*Embed\s*$", "", t.strip())
    t = re.sub(r"You might also like", "\n", t)
    t = re.sub(r"See .{1,80} LiveGet tickets as low as \$\d+", "", t)
    return re.sub(r"\n{3,}", "\n\n", t).strip()


def _genius_lyrics(token, artist, title):
    try:
        import lyricsgenius
        genius = lyricsgenius.Genius(token, skip_non_songs=True, remove_section_headers=False, timeout=TIMEOUT, retries=1, verbose=False)
        song = genius.search_song(search_form(title), artist)
        if not song:
            return ""
        if similarity(getattr(song, "title", ""), title) < 0.6:
            return ""
        if artist and similarity(getattr(song, "artist", ""), artist) < 0.6:
            return ""
        return _clean_genius(getattr(song, "lyrics", ""))
    except Exception:
        return ""


def scrape_metadata(artist_name, song_title, genius_token="", duration_ms=0, album=""):
    if not (song_title or "").strip():
        return json.dumps({"status": "error", "message": "Title required."})
    duration_ms = int(duration_ms or 0)
    artist, title, track_from_title = split_artist_title(artist_name or "", song_title)
    q_artist, q_title = search_form(artist), search_form(title)

    candidates, errors = [], []
    for name, fn in (("itunes", _itunes), ("deezer", _deezer), ("musicbrainz", _musicbrainz)):
        try:
            candidates.extend(fn(q_artist, q_title))
        except Exception as e:
            errors.append(f"{name}: {e}")

    for c in candidates:
        c["score"] = score_candidate(c, artist, title, duration_ms)
        c["score"] += {"itunes": 0.004, "deezer": 0.002}.get(c["source"], 0.0)
    candidates.sort(key=lambda c: c["score"], reverse=True)

    seen, unique = set(), []
    for c in candidates:
        key = (_norm(c["title"]), _norm(c["artist"]), _norm(c["album"]))
        if key in seen:
            continue
        seen.add(key)
        unique.append(c)
    unique = unique[:10]

    for c in unique[:3]:
        if c["source"] == "deezer":
            _deezer_details(c)

    best = unique[0] if unique else None
    confidence = min(1.0, round(best["score"], 3)) if best else 0.0

    lyr_artist = best["artist"] if best and confidence >= 0.8 else artist
    lyr_title = (best.get("search_title") or best["title"]) if best and confidence >= 0.8 else title
    lyr_album = best["album"] if best and confidence >= 0.8 else album
    lyr_duration = duration_ms or (best["duration_ms"] if best and confidence >= 0.8 else 0)
    lyrics = json.loads(fetch_lyrics(lyr_artist, lyr_title, lyr_album, lyr_duration))
    if not lyrics["plain"] and genius_token:
        plain = _genius_lyrics(genius_token, lyr_artist, lyr_title)
        if plain:
            lyrics = {"status": "success", "plain": plain, "synced": "", "source": "genius"}

    b = best or {}
    return json.dumps({
        "status": "success",
        "query": {"artist": artist, "title": title, "track_no": track_from_title},
        "confidence": confidence,
        "best": best,
        "candidates": unique,
        "lyrics_plain": lyrics.get("plain", ""),
        "lyrics_synced": lyrics.get("synced", ""),
        "lyrics_source": lyrics.get("source", ""),
        "errors": errors,
        "title": b.get("title") or title,
        "artist": b.get("artist") or artist,
        "album": b.get("album", ""),
        "album_artist": b.get("album_artist", ""),
        "year": b.get("year", ""),
        "genre": b.get("genre", ""),
        "track_no": b.get("track_no") or track_from_title,
        "disc_no": b.get("disc_no", ""),
        "lyrics": lyrics.get("synced") or lyrics.get("plain", ""),
        "artwork_url": b.get("artwork_url", ""),
    })


def fetch_artwork(url):
    if not url:
        return json.dumps({"status": "error", "message": "No artwork URL."})
    last = None
    for attempt in range(2):
        try:
            data = _get(url, headers={"Accept": "image/*"}, timeout=15, limit=MAX_ART_BYTES)
            if len(data) < 256:
                raise ValueError("Artwork payload too small")
            return json.dumps({"status": "success", "artwork_base64": base64.b64encode(data).decode("ascii")})
        except Exception as e:
            last = e
            time.sleep(0.4)
    return json.dumps({"status": "error", "message": str(last)})
