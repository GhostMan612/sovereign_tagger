// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;

enum GhostTone { info, happy, sarcastic }

class GhostReply {
  final String text;
  final GhostTone tone;
  final List<String> chips;
  final bool laugh;
  final bool hide;

  const GhostReply(this.text, {this.tone = GhostTone.info, this.chips = const [], this.laugh = false, this.hide = false});
}

class GhostTrack {
  final String path;
  final String title;
  final String artist;
  final String album;
  final int trackNo;
  final int discNo;

  const GhostTrack({required this.path, required this.title, required this.artist, required this.album, this.trackNo = 0, this.discNo = 0});
}

abstract class GhostWorld {
  int get currentTab;
  bool get hasMedia;
  bool get isPlaying;
  String get nowTitle;
  String get nowArtist;
  int get queueLength;
  bool get shuffle;
  String get repeat;
  bool get currentIsFavorite;

  Future<List<GhostTrack>> library();
  Future<void> play();
  Future<void> pause();
  void next();
  void previous();
  void setShuffle(bool on);
  void setRepeat(String mode);
  void setSleepMinutes(int minutes);
  void setSleepAtEndOfTrack(bool on);
  Future<void> playTracks(List<GhostTrack> tracks, {bool shuffle = false});
  Future<void> queueTracks(List<GhostTrack> tracks, {bool next = false});
  void openTab(int index);
  void openPlayer();
  void openSettings();
  void openEq();
  void openPlaybackEngine();
  void grab(String url);
  bool forgeCurrent();
  bool toggleFavoriteCurrent();
  Future<bool> openUrl(String url);
}

class _Query {
  final List<String> rawWords;
  final List<String> words;
  final Set<String> rawSet;
  final Set<String> set;
  final String rawText;

  _Query(this.rawWords, this.words)
      : rawSet = rawWords.toSet(),
        set = words.toSet(),
        rawText = ' ${rawWords.join(' ')} ';
}

class _KbEntry {
  final String id;
  final String title;
  final String keys;
  final List<String> details;
  final List<String> chips;

  const _KbEntry(this.id, this.title, this.keys, this.details, [this.chips = const []]);
}

enum _Verb { play, shuffle, queue, next }

class GhostBrain {
  final GhostWorld world;
  final math.Random _rng;

  _KbEntry? _lastEntry;
  int _lastDetail = 0;
  List<GhostTrack> _choices = const [];
  _Verb _choiceVerb = _Verb.play;

  GhostBrain(this.world, {math.Random? random}) : _rng = random ?? math.Random();

  static final RegExp _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

  static const Map<String, String> _synonyms = {
    'skip': 'next', 'forward': 'next', 'nxt': 'next',
    'prev': 'previous', 'back': 'previous', 'backward': 'previous', 'rewind': 'previous',
    'stop': 'pause', 'halt': 'pause', 'freeze': 'pause', 'mute': 'pause',
    'resume': 'resume', 'unpause': 'resume', 'continue': 'resume',
    'download': 'grab', 'rip': 'grab', 'fetch': 'grab', 'downloader': 'grabber', 'downloading': 'grab', 'downloads': 'grab',
    'tagger': 'forge', 'editor': 'forge', 'tagging': 'tag', 'tags': 'tag', 'metadata': 'tag', 'retag': 'tag',
    'pipeline': 'batch', 'bulk': 'batch', 'mass': 'batch',
    'studio': 'workbench', 'dsp': 'workbench', 'mastering': 'workbench',
    'songs': 'song', 'track': 'song', 'tracks': 'song', 'tune': 'song', 'tunes': 'song', 'music': 'song',
    'equalizer': 'eq', 'equaliser': 'eq', 'bass': 'eq', 'treble': 'eq',
    'fav': 'favorite', 'favourite': 'favorite', 'favorites': 'favorite', 'favourites': 'favorite', 'like': 'favorite', 'love': 'favorite', 'heart': 'favorite',
    'loop': 'repeat', 'looping': 'repeat',
    'random': 'shuffle', 'shuffled': 'shuffle', 'shuffling': 'shuffle',
    'artwork': 'art', 'cover': 'art', 'covers': 'art', 'picture': 'art', 'image': 'art', 'thumbnail': 'art',
    'lyric': 'lyrics', 'karaoke': 'lyrics', 'lrc': 'lyrics', 'words': 'lyrics',
    'setting': 'settings', 'preferences': 'settings', 'options': 'settings', 'config': 'settings',
    'playlists': 'playlist', 'mixtape': 'playlist',
    'timer': 'sleep', 'bedtime': 'sleep',
    'yt': 'youtube', 'ytdlp': 'youtube',
    'hello': 'hi', 'hey': 'hi', 'yo': 'hi', 'sup': 'hi', 'greetings': 'hi', 'howdy': 'hi',
    'thanks': 'thank', 'thx': 'thank', 'ty': 'thank', 'cheers': 'thank',
    'minutes': 'min', 'minute': 'min', 'mins': 'min', 'hours': 'hour', 'hrs': 'hour', 'hr': 'hour',
    'dupes': 'duplicate', 'duplicates': 'duplicate', 'copies': 'duplicate',
    'perms': 'permission', 'permissions': 'permission', 'allow': 'permission',
    'sfx': 'sound', 'sounds': 'sound', 'haptic': 'haptics', 'vibration': 'haptics',
    'colour': 'color', 'theme': 'color', 'accent': 'color',
  };

  static const Map<String, int> _tabs = {
    'grabber': 0, 'grab': 0, 'forge': 1, 'batch': 2, 'workbench': 3, 'library': 4,
  };

  static const List<_KbEntry> _kb = [
    _KbEntry('grab', 'How do I download?', 'grab grabber youtube soundcloud link url paste share save audio song video hunt search',
        [
          "GRABBER: paste a link (or SHARE one into the app from YouTube), then GRAB AUDIO NOW. No link? Type artist + title and HUNT on YOUTUBE or SOUNDCLOUD.",
          "Each finished download becomes a card. Nothing lands in Music until you tap SAVE TO MUSIC — or SEND TO FORGE to polish tags first.",
          "Paste a link right here and I'll hand it to the Grabber for you.",
        ],
        ['Audio formats', 'After a download', 'Downloads failing']),
    _KbEntry('modes', 'Audio formats', 'format mode m4a mp3 320 original quality aac bitrate lossless as-is encode convert audio grab',
        [
          "AUDIO MODES: M4A ORIGINAL (default) keeps YouTube's AAC stream untouched — best quality, zero re-encode. MP3 320K converts for old players. AS-IS keeps whatever the site sent (opus/webm can't hold tags).",
          "M4A downloads are remuxed losslessly so tags, cover art and the real duration stick. MAX AUDIO / QUICK VIDEO / 1080P / 720P live in the same panel.",
        ],
        ['How do I download?', 'After a download']),
    _KbEntry('cards', 'After a download', 'card cards edit rename file name title artist album cover art thumbnail save music send forge discard play grab after finished',
        [
          "Download cards let you fix TITLE, ARTIST, ALBUM, track and FILE NAME before anything is saved. COVER ART uses the video thumbnail, square-cropped.",
          "Buttons: PLAY previews it, SAVE TO MUSIC writes tags and files it, SEND TO FORGE opens it in the tag editor, DISCARD throws it away.",
        ],
        ['Audio formats', 'Editing tags']),
    _KbEntry('playlistgrab', 'Grab a whole playlist', 'playlist harvest whole album channel many multiple grab download batch',
        ["HARVEST PLAYLIST downloads every entry of a playlist link as its own card. SAVE ALL files them in one go."],
        ['After a download']),
    _KbEntry('grabfail', 'Downloads failing', 'fail failing error broken youtube not working update yt-dlp python grab crash stuck 403 sign in',
        [
          "When YouTube changes things, open SETTINGS → FULL STACK REFRESH (YT-DLP + DEPS). That updates the downloader engine in place.",
          "Still stuck? ON-BOARD PYTHON DOCTOR in Settings checks the engine. Silent Facebook videos self-heal by pulling a separate audio stream.",
        ],
        ['Open settings']),
    _KbEntry('forge', 'Editing tags', 'forge tag edit fix title artist album year genre mount file rename name song',
        [
          "FORGE is the tag editor. MOUNT AUDIO FILE, or use EDIT IN FORGE from the Library or the player. Nothing touches the file until you save.",
          "FILE NAME ON SAVE renames it too — AUTO NAME FROM TAGS builds 'NN - Artist - Title'. STRIP TO CORE and CLEAR ALL FIELDS only change the form.",
          "Say 'fix this song' and I'll open whatever is playing in the Forge.",
        ],
        ['Auto-tag a song', 'Save & fix original', 'Find lyrics']),
    _KbEntry('forgesave', 'Save & fix original', 'save fix original copy overwrite replace in place permission duplicate write forge',
        [
          "SAVE & FIX ORIGINAL rewrites the song where it lives — Android asks once for permission to modify it. No duplicate is created.",
          "SAVE COPY writes a new file to Music instead. After saving, the Forge reads the tags back to prove they stuck.",
        ],
        ['Why duplicates?', 'Permission prompts']),
    _KbEntry('autotag', 'Auto-tag a song', 'auto tag automatic search metadata identify fingerprint acr spider match correct wrong album year review apply',
        [
          "SEARCH METADATA asks iTunes, Deezer and MusicBrainz, scores the matches, and shows a review sheet — tick what to change, then APPLY. It fixes wrong fields, not just empty ones.",
          "IDENTIFY fingerprints the audio itself (needs ACRCloud keys in Settings) — best for files with junk names.",
        ],
        ['Editing tags', 'Get API keys']),
    _KbEntry('lyrics', 'Find lyrics', 'lyrics lyric karaoke sync synced lrc words find embed lrclib genius',
        [
          "In the FORGE: FIND pulls lyrics (synced when available) from LRCLIB; the KARAOKE MACHINE (SYNC) lets you stamp timings yourself. They're embedded on save.",
          "In the player, the lyrics button shows embedded lyrics, a sidecar .lrc, or FIND LYRICS ONLINE — then EMBED INTO FILE VIA FORGE to keep them.",
        ],
        ['Editing tags']),
    _KbEntry('art', 'Album art', 'art cover artwork picture image thumbnail missing show player not showing blank folder jpg',
        [
          "The player shows art embedded in the file first, then asks Android's own extractor, then looks for cover.jpg / folder.jpg beside the song.",
          "Add or replace art in the FORGE with BROWSE ART (CLEAR ART removes it), then SAVE & FIX ORIGINAL. Grabber cards use the video thumbnail.",
          "Folder images need Photos access on Android 13+ — embedded art always works.",
        ],
        ['Editing tags', 'Save & fix original']),
    _KbEntry('batch', 'How does batch work?', 'batch many multiple bulk all library execute review fix whole collection',
        [
          "BATCH fixes many songs at once: FROM LIBRARY picks them, EXECUTE BATCH runs the search. Android asks once for permission to modify them all.",
          "Confident matches are fixed in place; unsure ones wait in REVIEW — OPEN IN FORGE to finish them. RENAME FILES TO ARTIST - TITLE and USE COPIES are options. Long-press to RE-IDENTIFY FROM SCRATCH.",
        ],
        ['Save & fix original']),
    _KbEntry('library', 'The library', 'library songs albums artists folders new browse search find play all shuffle long press menu delete',
        [
          "LIBRARY shows every song on the phone: SONGS, ALBUMS, ARTISTS, FOLDERS, PLAYLISTS and NEW. Search filters live; PLAY ALL or SHUFFLE any list.",
          "Long-press a song for PLAY NEXT, ADD TO QUEUE, ADD TO PLAYLIST, ADD TO FAVORITES, EDIT IN FORGE or DELETE FROM DEVICE.",
          "Or just tell me: 'play <artist>', 'shuffle everything', 'queue <song>'.",
        ],
        ['Playlists', 'Shuffle everything']),
    _KbEntry('playlists', 'Playlists', 'playlist playlists favorite favorites recently played save queue new create rename',
        [
          "NEW PLAYLIST lives under LIBRARY → PLAYLISTS, next to Favorites and RECENTLY PLAYED. Long-press any song → ADD TO PLAYLIST.",
          "In the player queue, SAVE AS PLAYLIST keeps the current queue. Say 'favorite this' and I'll heart what's playing.",
        ],
        ['The library']),
    _KbEntry('player', 'Using the player', 'player now playing full screen mini queue reorder swipe zoom double tap seek controls skip',
        [
          "Tap the mini-player for full screen. Pinch-zoom the art, double-tap left/right to seek 10 s.",
          "The queue: drag to reorder, swipe to remove, SAVE AS PLAYLIST. TRACK OPTIONS has play next, favorites, playlists and EDIT IN FORGE.",
        ],
        ['Equalizer', 'Sleep timer', 'Playback engine']),
    _KbEntry('eq', 'Equalizer', 'eq equalizer bass treble preset sound curve band boost',
        [
          "The tune icon in the player opens the EQUALIZER — presets and your 15-band curve are mapped onto the phone's EQ and heard live. Flip the bypass switch to compare.",
          "Say 'open eq' and I'll take you there.",
        ],
        ['Playback engine']),
    _KbEntry('engine', 'Playback engine', 'engine replaygain loudness volume normalize fade crossfade preamp gain quiet loud',
        [
          "PLAYBACK ENGINE (merge icon in the player): FADE OUT / FADE IN between tracks and ReplayGain (track or album) with a PRE-AMP, so every song plays at an even loudness.",
          "ReplayGain needs tags — scan them in WORKBENCH → REPLAYGAIN SCANNER (EBU R128).",
        ],
        ['ReplayGain scan', 'Equalizer']),
    _KbEntry('sleep', 'Sleep timer', 'sleep timer bedtime stop after minutes end track speed playback',
        [
          "Player → SLEEP TIMER: pick minutes (it fades out) or END OF TRACK. PLAYBACK SPEED sits beside it.",
          "Or tell me: 'sleep in 30 min', 'stop after this song', 'cancel sleep'.",
        ],
        ['Using the player']),
    _KbEntry('workbench', 'The workbench', 'workbench studio dsp eq loudness reverb pitch tempo fade trim erase reverse record master effect',
        [
          "WORKBENCH is the audio lab: MOUNT MEDIA, then 15-BAND PARAMETRIC EQ (AutoEq), TWO-PASS LOUDNORM, SPATIAL REVERB, TEMPO / PITCH WARP, FADE IN/OUT, REGION TO ERASE, INVERT WAVEFORM (REVERSE) — then EXECUTE ON THE MACHINE.",
          "Lossless files stay lossless. LOSSLESS PCM (48K WAV) records true 48k/16-bit audio.",
        ],
        ['ReplayGain scan', 'Transcribe with Whisper']),
    _KbEntry('replaygain', 'ReplayGain scan', 'replaygain scan loudness lufs normalize volume r128 tag gain',
        ["WORKBENCH → REPLAYGAIN SCANNER (EBU R128) → SCAN REPLAYGAIN writes gain tags. The player's PLAYBACK ENGINE uses them to even out volume. SCAN LUFS measures without writing."],
        ['Playback engine']),
    _KbEntry('whisper', 'Transcribe with Whisper', 'whisper transcribe transcription speech text subtitle words ai model',
        ["WORKBENCH has Whisper transcription. The first run downloads the model (about 140 MB), then it works offline."],
        ['The workbench']),
    _KbEntry('keys', 'Get API keys', 'api key keys genius acr acrcloud token fingerprint identify write kernel',
        [
          "Keys are optional: metadata search and lyrics work without them. ACRCloud is only for IDENTIFY (audio fingerprint); Genius is an extra lyrics source.",
          "Say 'open acr' or 'open genius' and I'll launch the sign-up page. Paste keys in SETTINGS and tap WRITE TO KERNEL.",
        ],
        ['Open ACR console', 'Open Genius signup']),
    _KbEntry('look', 'Colors, sounds & effects', 'color accent theme sound haptics effect burst ring pulse feedback animation motion reduce look',
        [
          "SETTINGS → SELECT ACCENT COLOR recolors the whole machine. The FEEDBACK MATRIX toggles PARTICLE BURST, SHOCKWAVE RING, SCALE PULSE, SOUND FX and HAPTICS.",
          "REDUCE MOTION (GLOBAL) calms animations — including me. Tap sounds never duck your music.",
        ],
        ['Open settings']),
    _KbEntry('backup', 'Backup & cache', 'backup restore export import cache purge clear storage space probe ffmpeg',
        ["SETTINGS: BACKUP ALL / RESTORE ALL save and restore your setup. PURGE INTERNAL CACHE frees space. FFMPEG KERNEL PROBE checks the audio engine."],
        ['Open settings']),
    _KbEntry('widget', 'Home screen widget', 'widget home screen launcher lock controls buttons notification',
        ["Long-press your home screen → Widgets → Sovereign Tagger. Its buttons control playback and it shows what's playing. The lock screen shows art and controls too."],
        ['Using the player']),
    _KbEntry('share', 'Share links into the app', 'share link youtube app send open with intent',
        ["In YouTube (or any app) tap Share → Sovereign Tagger. The Grabber opens with the link filled in."],
        ['How do I download?']),
    _KbEntry('permission', 'Permission prompts', 'permission prompt allow ask modify access denied android popup',
        [
          "Android asks before any app rewrites a song it didn't create. SAVE & FIX ORIGINAL asks once per save; BATCH asks once for the whole batch.",
          "Deny it and the machine saves a copy instead, so nothing is lost.",
        ],
        ['Save & fix original', 'Why duplicates?']),
    _KbEntry('duplicate', 'Why duplicates?', 'duplicate duplicates copies twice double copy same song again',
        ["Duplicates came from old builds that saved a new copy every time. Now SAVE & FIX ORIGINAL rewrites in place; a copy only appears if you choose SAVE COPY or deny permission."],
        ['Save & fix original']),
    _KbEntry('self', 'What can you do?', 'ghost you your help commands abilities can do what who are',
        [
          "I run the machine by voice-of-text: 'play <artist>', 'shuffle everything', 'next', 'pause', 'repeat one', 'sleep in 20 min', 'what's playing', 'favorite this', 'fix this song', 'open forge', 'open eq' — or paste a link to grab it.",
          "Ask me how anything works: 'how do I download', 'why is there no album art', 'batch', 'lyrics'. I'm fully offline — no fees, no cloud.",
        ],
        ['Shuffle everything', "What's playing?", 'How do I download?']),
  ];

  static final Map<String, List<String>> _index = {
    for (final e in _kb) e.id: _terms(e.id == 'self' ? '${e.title} ${e.keys} ${e.keys}' : '${e.title} ${e.keys} ${e.keys} ${e.details.join(' ')}'),
  };
  static final Set<String> _vocabulary = {
    for (final terms in _index.values) ...terms,
    ..._synonyms.keys,
    ..._synonyms.values,
    ..._tabs.keys,
    'play', 'pause', 'next', 'previous', 'shuffle', 'repeat', 'sleep', 'queue', 'open', 'show', 'favorite', 'what', 'playing',
    'everything', 'playlist', 'settings', 'player', 'cancel', 'after', 'song', 'hide', 'laugh', 'joke',
  };

  List<String> suggestionsFor(int tab) {
    switch (tab) {
      case 0:
        return const ['How do I download?', 'Audio formats', 'Downloads failing', 'What can you do?'];
      case 1:
        return const ['Auto-tag a song', 'Save & fix original', 'Find lyrics', 'Fix this song'];
      case 2:
        return const ['How does batch work?', 'Permission prompts', 'What can you do?'];
      case 3:
        return const ['ReplayGain scan', 'Transcribe with Whisper', 'The workbench'];
      case 4:
        return const ['Shuffle everything', "What's playing?", 'Playlists', 'Open EQ'];
      default:
        return const ['What can you do?', "What's playing?", 'Open settings'];
    }
  }

  Future<GhostReply> respond(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return GhostReply(_pick(const ["Say something. I'm listening.", "Static on the line — try again."]));

    final url = _urlPattern.firstMatch(raw)?.group(0);
    if (url != null) {
      world.grab(url);
      return GhostReply(_pick(const ["Link captured. The GRABBER has it — pick a mode and GRAB AUDIO NOW.", "Target locked. Grabber loaded with your link."]), tone: GhostTone.happy);
    }

    final rawWords = _tokens(raw);
    final words = _correct(rawWords);
    final q = _Query(rawWords, words);

    final choice = await _resolveChoice(raw, words);
    if (choice != null) return choice;

    if (_lastEntry != null && _isFollowUp(q)) return _continueEntry();

    final social = _social(q);
    if (social != null) return social;

    final special = await _special(q.rawText);
    if (special != null) return special;

    final command = await _command(q);
    if (command != null) return command;

    return _knowledge(words);
  }

  Future<GhostReply?> _resolveChoice(String raw, List<String> words) async {
    if (_choices.isEmpty) return null;
    final choices = _choices;
    final verb = _choiceVerb;
    int? index;
    const strong = {'first': 0, '1': 0, 'second': 1, '2': 1, 'third': 2, '3': 2};
    const weak = {'one': 0, 'two': 1, 'three': 2};
    for (final w in words) {
      if (strong.containsKey(w)) {
        index = strong[w];
        break;
      }
    }
    if (index == null && words.contains('last')) index = choices.length - 1;
    if (index == null) {
      for (final w in words) {
        if (weak.containsKey(w)) {
          index = weak[w];
          break;
        }
      }
    }
    if (words.contains('all') || words.contains('them') || words.contains('both')) {
      _choices = const [];
      return _performTracks(verb, choices, 'all ${choices.length}');
    }
    if (index == null) {
      final best = _bestTitleMatch(raw, choices);
      if (best != null) index = choices.indexOf(best);
    }
    if (index == null || index >= choices.length) {
      _choices = const [];
      return null;
    }
    _choices = const [];
    final picked = choices[index];
    return _performTracks(verb, [picked], '${picked.title} — ${_artistOr(picked)}');
  }

  bool _isFollowUp(_Query q) {
    if (q.rawWords.isEmpty || q.rawWords.length > 5) return false;
    final text = q.rawText;
    const phrases = [' more ', ' go on ', ' what else ', ' and then ', ' keep going ', ' elaborate ', ' tell me more ', ' then what ', ' continue '];
    if (phrases.any(text.contains)) return true;
    return q.rawWords.length == 1 && const {'and', 'then', 'so', 'ok', 'okay'}.contains(q.rawWords.first);
  }

  GhostReply _continueEntry() {
    final entry = _lastEntry!;
    _lastDetail++;
    if (_lastDetail >= entry.details.length) {
      _lastDetail = entry.details.length - 1;
      return GhostReply("That's everything I know about ${entry.title.toLowerCase().replaceAll('?', '')}. Try one of these:", chips: entry.chips.isEmpty ? suggestionsFor(world.currentTab) : entry.chips);
    }
    return GhostReply(entry.details[_lastDetail], chips: entry.chips);
  }

  GhostReply? _social(_Query q) {
    final set = q.set;
    final text = q.rawText;
    if (set.contains('hi') && set.length <= 3) {
      final now = world.hasMedia && world.nowTitle.isNotEmpty ? " You're listening to ${world.nowTitle}." : '';
      return GhostReply(_pick(["Signal acquired.$now What do you need?", "Hey, operator.$now Ask me anything — or give me an order.", "Boo.$now Kidding. What can I do for you?"]), tone: GhostTone.happy, chips: suggestionsFor(world.currentTab));
    }
    if (set.contains('thank')) {
      return GhostReply(_pick(const ["Anytime. I live here.", "No charge. I'm free-range and offline.", "Happy haunting."]), tone: GhostTone.happy);
    }
    if (text.contains(' hide ') || text.contains(' go away ') || text.contains(' dismiss ') || text.contains(' bye ') || text.contains(' goodbye ')) {
      return GhostReply(_pick(const ["Fading out. Tap me when you need me.", "Going dark. I'll be in the walls."]), hide: true);
    }
    if (set.contains('joke') || set.contains('laugh') || set.contains('skynet') || text.contains(' funny ')) {
      return GhostReply(_pick(const [
        "Why don't ghosts use streaming? They prefer to download their spirits. Hahaha!",
        "Activating SkyNet... just kidding. I only have jurisdiction over your music. Hahaha!",
        "I tried to haunt a vinyl collection once. Too many skips. Hahaha!",
      ]), tone: GhostTone.sarcastic, laugh: true);
    }
    if (text.contains(' what can you do ') || text.contains(' what do you do ') || text.contains(' commands ') || q.rawWords.length == 1 && q.rawWords.first == 'help') {
      final entry = _kb.firstWhere((e) => e.id == 'self');
      _lastEntry = entry;
      _lastDetail = 0;
      return GhostReply(entry.details.first, tone: GhostTone.happy, chips: entry.chips);
    }
    if ((text.contains(' who are you ') || text.contains(' what are you ') || text.contains(' your name ')) && !text.contains(' playing ')) {
      return const GhostReply("I'm the ghost in the machine — your offline co-pilot. I know every button in here and I can drive the player for you.", tone: GhostTone.happy, chips: ['What can you do?']);
    }
    if (text.contains(' good ghost ') || text.contains(' love you ') || text.contains(' you rock ') || text.contains(' good job ') || text.contains(' nice ')) {
      return GhostReply(_pick(const ["*glows brighter*", "Flattery accepted. Processing joy.", "Stop, you'll make me materialize."]), tone: GhostTone.happy);
    }
    return null;
  }

  Future<GhostReply?> _special(String text) async {
    if (text.contains(' open genius ') || text.contains(' genius signup ') || text.contains(' genius sign up ')) {
      final ok = await world.openUrl('https://genius.com/api-clients');
      return GhostReply(ok ? "Genius API page launched. Create a client, copy the CLIENT ACCESS TOKEN, paste it in SETTINGS → WRITE TO KERNEL." : "Browser fault. Open genius.com/api-clients yourself.");
    }
    if (text.contains(' open acr ') || text.contains(' acr console ') || text.contains(' acr signup ') || text.contains(' open acrcloud ')) {
      final ok = await world.openUrl('https://console.acrcloud.com/');
      return GhostReply(ok ? "ACRCloud console launched. Audio & Video Recognition → Create Project → Recorded Audio, then copy host, key and secret into SETTINGS." : "Browser fault. Open console.acrcloud.com yourself.");
    }
    return null;
  }

  Future<GhostReply?> _command(_Query q) async {
    final words = q.words;
    final set = q.set;
    final text = q.rawText;
    final isQuestion = text.contains(' how ') || text.contains(' why ') || set.contains('help') || text.contains(' explain ') || text.contains(' where ');

    if (!isQuestion && (text.contains(' what is playing ') || text.contains(' whats playing ') || text.contains(' now playing ') || text.contains(' what song ') || text.contains(' what track ') || text.contains(' who is this ') || text.contains(' who sings ') || text.contains(' current song ') || text.contains(' what is this song ') || text.contains(' what is this '))) {
      if (!world.hasMedia) return const GhostReply("Nothing's loaded. Try 'shuffle everything' or 'play <artist>'.", chips: ['Shuffle everything']);
      final artist = world.nowArtist.trim();
      final state = world.isPlaying ? 'Playing' : 'Paused on';
      final queue = world.queueLength > 1 ? ' ${world.queueLength} in the queue.' : '';
      return GhostReply("$state ${world.nowTitle}${artist.isEmpty || artist.startsWith('[') ? '' : ' by $artist'}.$queue", tone: GhostTone.happy, chips: const ['Next', 'Favorite this', 'Fix this song']);
    }

    if (text.contains(' how many ') || set.contains('count')) {
      return _count(q);
    }

    if (isQuestion) return null;

    final sleep = _sleep(q);
    if (sleep != null) return sleep;

    if (set.contains('open') || set.contains('show') || text.contains(' go to ') || text.contains(' take me ') || text.contains(' switch to ')) {
      final nav = _navigate(set, text);
      if (nav != null) return nav;
    }

    if (text.contains(' fix this ') || text.contains(' tag this ') || text.contains(' edit this ') || text.contains(' forge this ') || text.contains(' fix it ') || text.contains(' fix the tags ') || (set.contains('forge') && (set.contains('this') || set.contains('current') || set.contains('it')))) {
      if (!world.forgeCurrent()) return const GhostReply("Nothing is playing to fix. Mount a file in the FORGE, or play a song first.");
      return GhostReply(_pick(const ["Sent to the FORGE. Try SEARCH METADATA, review, then SAVE & FIX ORIGINAL.", "It's on the anvil. SEARCH METADATA → APPLY → SAVE & FIX ORIGINAL."]), tone: GhostTone.happy);
    }

    final pointsAtSong = q.rawSet.intersection(const {'this', 'it', 'current', 'song', 'track', 'tune'}).isNotEmpty;
    if (set.contains('favorite') && (pointsAtSong || q.rawWords.length == 1)) {
      if (!world.hasMedia) return const GhostReply("Nothing's playing to favorite.");
      final removing = text.contains(' unfavorite ') || text.contains(' remove ') || text.contains(' unlike ') || text.contains(' unheart ');
      if (removing && !world.currentIsFavorite) return GhostReply("${world.nowTitle} isn't in Favorites.");
      if (!removing && world.currentIsFavorite) return GhostReply("${world.nowTitle} is already a favorite. Say 'unfavorite this' to remove it.");
      world.toggleFavoriteCurrent();
      return GhostReply(removing ? "Removed ${world.nowTitle} from Favorites." : "♥ ${world.nowTitle} added to Favorites.", tone: GhostTone.happy);
    }

    if (set.contains('repeat')) {
      String mode;
      if (set.contains('off') || set.contains('no') || q.rawSet.contains('stop') || set.contains('disable')) {
        mode = 'off';
      } else if (set.contains('one') || set.contains('this') || set.contains('song') || set.contains('single')) {
        mode = 'one';
      } else if (set.contains('all') || set.contains('queue') || set.contains('everything') || set.contains('playlist')) {
        mode = 'all';
      } else {
        mode = switch (world.repeat) { 'off' => 'all', 'all' => 'one', _ => 'off' };
      }
      world.setRepeat(mode);
      return GhostReply(switch (mode) { 'one' => 'Repeat ONE — this song on loop.', 'all' => 'Repeat ALL — the queue wraps around.', _ => 'Repeat OFF.' }, tone: GhostTone.happy);
    }

    final shuffleToggle = set.contains('shuffle') && q.rawWords.every((w) => const {'shuffle', 'on', 'off', 'turn', 'toggle', 'enable', 'disable', 'mode', 'please', 'random'}.contains(w));
    if (shuffleToggle) {
      final on = set.contains('off') || set.contains('disable') ? false : (set.contains('on') || set.contains('enable') ? true : !world.shuffle);
      world.setShuffle(on);
      return GhostReply(on ? 'Shuffle ON. Chaos engaged.' : 'Shuffle OFF. Order restored.', tone: GhostTone.happy);
    }

    final playVerb = q.rawSet.intersection(const {'play', 'put', 'listen', 'queue', 'add', 'shuffle', 'blast', 'spin'}).isNotEmpty;
    if (playVerb && q.rawWords.length > 1) {
      final result = await _playSomething(q);
      if (result != null) return result;
    }

    if (words.length <= 3) {
      if (set.contains('pause')) {
        if (!world.hasMedia) return const GhostReply("Nothing's playing.");
        await world.pause();
        return GhostReply(_pick(const ['Paused.', 'Silence engaged.', 'Holding.']));
      }
      if (set.contains('resume') || set.contains('play')) {
        if (!world.hasMedia) return const GhostReply("The queue is empty. Try 'shuffle everything' or 'play <artist>'.", chips: ['Shuffle everything']);
        await world.play();
        return GhostReply(_pick(const ['Playing.', 'Resuming transmission.', 'Back on air.']), tone: GhostTone.happy);
      }
      if (set.contains('next')) {
        if (!world.hasMedia) return const GhostReply("Nothing to skip.");
        world.next();
        return GhostReply(_pick(const ['Skipped.', 'Next one.', 'Onward.']));
      }
      if (set.contains('previous') || (set.contains('last') && set.contains('song'))) {
        if (!world.hasMedia) return const GhostReply("Nothing to rewind.");
        world.previous();
        return GhostReply(_pick(const ['Going back.', 'Previous track.', 'Rewinding.']));
      }
    }

    return null;
  }

  GhostReply? _sleep(_Query q) {
    final set = q.set;
    final text = q.rawText;
    final hasNumber = RegExp(r'\d').hasMatch(text);
    final afterThis = text.contains(' after this ') || text.contains(' end of this ') || text.contains(' end of the song ') || text.contains(' after the song ') || text.contains(' end of track ');
    final stopPhrase = text.contains(' turn off ') || text.contains(' stop in ') || text.contains(' stop after ') || text.contains(' shut off ') || text.contains(' shut down ');
    final sleepy = set.contains('sleep') || (stopPhrase && (hasNumber || afterThis));
    if (!sleepy) return null;
    if (set.contains('cancel') || text.contains(' no sleep ') || (set.contains('sleep') && set.contains('off') && !hasNumber)) {
      world.setSleepMinutes(0);
      world.setSleepAtEndOfTrack(false);
      return const GhostReply('Sleep timer cancelled.');
    }
    if (afterThis) {
      world.setSleepAtEndOfTrack(true);
      return const GhostReply('Playback stops at the end of this track.', tone: GhostTone.happy);
    }
    final match = RegExp(r'(\d+)\s*(min|minute|minutes|mins|m|hour|hours|hr|hrs|h)?\b').firstMatch(text);
    if (match == null) return const GhostReply("How long? Try 'sleep in 30 min' or 'stop after this song'.", chips: ['Sleep in 30 min', 'Stop after this song']);
    var minutes = int.parse(match.group(1)!);
    final unit = match.group(2) ?? '';
    if (unit.startsWith('h')) minutes *= 60;
    minutes = minutes.clamp(1, 600);
    world.setSleepMinutes(minutes);
    return GhostReply('Sleep timer set: $minutes min. The music fades out, then stops.', tone: GhostTone.happy);
  }

  GhostReply? _navigate(Set<String> set, String text) {
    if (set.contains('eq')) {
      world.openEq();
      return const GhostReply('Opening the EQUALIZER.');
    }
    if (set.contains('engine') || set.contains('replaygain') || text.contains(' playback engine ')) {
      world.openPlaybackEngine();
      return const GhostReply('Opening the PLAYBACK ENGINE.');
    }
    if (set.contains('settings')) {
      world.openSettings();
      return const GhostReply('Opening SETTINGS.');
    }
    if (set.contains('player') || set.contains('queue') || text.contains(' now playing ')) {
      world.openPlayer();
      return const GhostReply('Opening the player.');
    }
    for (final entry in _tabs.entries) {
      if (set.contains(entry.key)) {
        world.openTab(entry.value);
        return GhostReply('Switching to ${const ['GRABBER', 'FORGE', 'BATCH', 'WORKBENCH', 'LIBRARY'][entry.value]}.', chips: suggestionsFor(entry.value));
      }
    }
    return null;
  }

  Future<GhostReply?> _playSomething(_Query q) async {
    final raw = q.rawWords;
    final rawSet = q.rawSet;
    final text = q.rawText;
    _Verb verb = _Verb.play;
    if (rawSet.contains('shuffle')) verb = _Verb.shuffle;
    if (rawSet.contains('queue') || rawSet.contains('add')) verb = _Verb.queue;
    if (text.contains(' play next ') || text.contains(' up next ') || text.contains(' next in the queue ') || (verb == _Verb.play && raw.length > 2 && raw.last == 'next')) verb = _Verb.next;

    const lead = {'can', 'you', 'could', 'would', 'please', 'i', 'want', 'wanna', 'to', 'lets', 'let', 'us', 'me', 'just', 'now', 'go', 'ahead', 'and', 'play', 'put', 'on', 'listen', 'queue', 'add', 'shuffle', 'blast', 'spin', 'some', 'a', 'an', 'up'};
    const trail = {'please', 'now', 'next', 'for', 'me', 'up', 'on', 'shuffle', 'queue', 'to', 'the', 'in', 'my'};
    var start = 0;
    while (start < raw.length && lead.contains(raw[start])) {
      start++;
    }
    var end = raw.length;
    while (end > start && trail.contains(raw[end - 1])) {
      end--;
    }
    var rest = raw.sublist(start, end);

    const libraryWords = {'everything', 'all', 'library', 'my', 'songs', 'song', 'music', 'tracks', 'track', 'the', 'of', 'it', 'something', 'anything', 'whole', 'random', 'stuff', 'tunes'};
    final wantsEverything = rest.isEmpty || (rest.every(libraryWords.contains) && rest.any((w) => const {'everything', 'all', 'library', 'something', 'anything', 'music', 'songs', 'random', 'stuff', 'tunes'}.contains(w)));
    final library = await world.library();
    if (library.isEmpty) return const GhostReply("I can't see any music yet. Open the LIBRARY once so Android grants access, then ask again.", chips: ['Open library']);

    if (wantsEverything) {
      await world.playTracks(List<GhostTrack>.of(library), shuffle: true);
      return GhostReply('Shuffling all ${library.length} songs. Let chaos decide.', tone: GhostTone.happy);
    }

    String? mode;
    if (rest.first == 'album' && rest.length > 1) {
      mode = 'album';
      rest = rest.sublist(1);
    } else if (rest.first == 'artist' && rest.length > 1) {
      mode = 'artist';
      rest = rest.sublist(1);
    } else if (rest.length > 2 && const {'songs', 'music', 'stuff', 'anything', 'something', 'tracks', 'tunes'}.contains(rest.first) && const {'by', 'from', 'of'}.contains(rest[1])) {
      mode = 'artist';
      rest = rest.sublist(2);
    }
    final query = rest.join(' ');
    if (query.trim().isEmpty) return null;

    if (mode == 'album') {
      final tracks = _byAlbum(library, query);
      if (tracks.isEmpty) return GhostReply("No album called '$query' here.", tone: GhostTone.sarcastic);
      return _performTracks(verb, tracks, 'the album ${tracks.first.album}');
    }
    if (mode == 'artist') {
      final tracks = _byArtist(library, query);
      if (tracks.isEmpty) return GhostReply("No songs by '$query' in your library.", tone: GhostTone.sarcastic, chips: const ['How do I download?']);
      return _performTracks(verb == _Verb.play ? _Verb.shuffle : verb, tracks, '${tracks.length} songs by ${tracks.first.artist}');
    }

    final byAt = rest.lastIndexOf('by');
    if (byAt > 0 && byAt < rest.length - 1) {
      final title = rest.sublist(0, byAt).join(' ');
      final who = rest.sublist(byAt + 1).join(' ');
      final artistTracks = _byArtist(library, who);
      if (artistTracks.isNotEmpty) {
        final ranked = _rankTitles(artistTracks, title);
        if (ranked.isNotEmpty) return _performTracks(verb, [ranked.first.key], '${ranked.first.key.title} — ${_artistOr(ranked.first.key)}');
        return GhostReply("${artistTracks.first.artist} is here, but no song like '$title'.", tone: GhostTone.sarcastic, chips: ['Play ${artistTracks.first.artist}']);
      }
    }

    final artistTracks = _byArtist(library, query);
    if (artistTracks.isNotEmpty) {
      return _performTracks(verb == _Verb.play ? _Verb.shuffle : verb, artistTracks, '${artistTracks.length} songs by ${artistTracks.first.artist}');
    }
    final albumTracks = _byAlbum(library, query);
    if (albumTracks.isNotEmpty) return _performTracks(verb, albumTracks, 'the album ${albumTracks.first.album}');

    final ranked = _rankTitles(library, query);
    if (ranked.isEmpty) {
      return GhostReply("No match for '$query' in your library. Check the spelling, or GRAB it.", tone: GhostTone.sarcastic, chips: const ['How do I download?']);
    }
    final top = ranked.first;
    final close = ranked.where((r) => r.value >= top.value - 0.08).map((r) => r.key).toList();
    if (close.length > 1 && top.value < 1.2) {
      _choices = close.take(3).toList();
      _choiceVerb = verb;
      final lines = [for (var i = 0; i < _choices.length; i++) '${i + 1}. ${_choices[i].title} — ${_artistOr(_choices[i])}'];
      return GhostReply('A few matches. Which one?\n${lines.join('\n')}', chips: [for (var i = 0; i < _choices.length; i++) '${i + 1}. ${_choices[i].title}']);
    }
    return _performTracks(verb, [top.key], '${top.key.title} — ${_artistOr(top.key)}');
  }

  Future<GhostReply> _performTracks(_Verb verb, List<GhostTrack> tracks, String label) async {
    switch (verb) {
      case _Verb.play:
        await world.playTracks(tracks);
        return GhostReply(_pick(['Now playing $label.', 'Loading $label.', 'On air: $label.']), tone: GhostTone.happy, chips: const ['Next', 'Favorite this']);
      case _Verb.shuffle:
        await world.playTracks(tracks, shuffle: true);
        return GhostReply('Shuffling $label.', tone: GhostTone.happy, chips: const ['Next', 'Repeat all']);
      case _Verb.queue:
        await world.queueTracks(tracks);
        return GhostReply('Queued $label.', tone: GhostTone.happy);
      case _Verb.next:
        await world.queueTracks(tracks, next: true);
        return GhostReply('$label plays next.', tone: GhostTone.happy);
    }
  }

  Future<GhostReply> _count(_Query q) async {
    final library = await world.library();
    if (library.isEmpty) return const GhostReply("I can't see any music yet — open the LIBRARY once to grant access.");
    final raw = q.rawWords;
    final byAt = raw.indexWhere((w) => w == 'by' || w == 'from');
    if (byAt >= 0 && byAt < raw.length - 1) {
      final who = raw.sublist(byAt + 1).where((w) => w != 'do' && w != 'i' && w != 'have').join(' ');
      final tracks = _byArtist(library, who);
      if (tracks.isEmpty) return GhostReply("No songs by '$who' here.");
      return GhostReply('${tracks.length} songs by ${tracks.first.artist}.', chips: ['Play ${tracks.first.artist}']);
    }
    if (q.rawSet.contains('album') || q.rawSet.contains('albums')) {
      final albums = library.map((t) => _norm(t.album)).where((a) => a.isNotEmpty).toSet().length;
      return GhostReply('$albums albums in your library.');
    }
    if (q.rawSet.contains('artist') || q.rawSet.contains('artists')) {
      final artists = library.map((t) => _norm(t.artist)).where((a) => a.isNotEmpty && !a.startsWith('unknown')).toSet().length;
      return GhostReply('$artists artists in your library.');
    }
    return GhostReply('${library.length} songs in your library.', chips: const ['Shuffle everything']);
  }

  GhostReply _knowledge(List<String> words) {
    final terms = words.map(_stem).where((w) => w.length > 1 && !_stop.contains(w)).toList();
    if (terms.isEmpty) {
      return GhostReply(_pick(const ["Signal unclear. Try one of these:", "Say that again, in human? Or pick one:"]), tone: GhostTone.sarcastic, chips: suggestionsFor(world.currentTab));
    }
    final scored = <MapEntry<_KbEntry, double>>[];
    final avg = _index.values.fold<int>(0, (s, t) => s + t.length) / _index.length;
    for (final entry in _kb) {
      final doc = _index[entry.id]!;
      var score = 0.0;
      for (final term in terms.toSet()) {
        final tf = doc.where((d) => d == term).length;
        if (tf == 0) continue;
        final df = _index.values.where((d) => d.contains(term)).length;
        final idf = math.log(1 + (_kb.length - df + 0.5) / (df + 0.5));
        score += idf * (tf * 2.2) / (tf + 1.2 * (0.25 + 0.75 * doc.length / avg));
      }
      final titleTerms = _terms(entry.title);
      if (titleTerms.isNotEmpty && titleTerms.every((t) => terms.contains(t))) score += 2.5;
      scored.add(MapEntry(entry, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    if (scored.first.value < 1.2) {
      return GhostReply("That one's outside my files. Closest things I know:", tone: GhostTone.sarcastic, chips: [for (final s in scored.take(3)) s.key.title]);
    }
    final entry = scored.first.key;
    _lastEntry = entry;
    _lastDetail = 0;
    final more = entry.details.length > 1 ? ' (say "more" for the rest)' : '';
    return GhostReply('${entry.details.first}$more', chips: entry.chips);
  }

  List<GhostTrack> _byArtist(List<GhostTrack> library, String query) {
    final q = _norm(query);
    if (q.length < 2) return const [];
    final groups = <String, List<GhostTrack>>{};
    for (final t in library) {
      final a = _norm(t.artist);
      if (a.isEmpty || a == 'unknown' || a.startsWith('unknown ')) continue;
      if (a == q || _similar(a, q) >= 0.88 || (q.length >= 4 && a.split(RegExp(r'\s*(?:,|&|feat|ft|x|and)\s*')).any((part) => part.trim() == q))) {
        groups.putIfAbsent(t.artist, () => []).add(t);
      }
    }
    if (groups.isEmpty) return const [];
    final all = groups.values.expand((g) => g).toList();
    all.sort((a, b) => _norm(a.album).compareTo(_norm(b.album)) != 0 ? _norm(a.album).compareTo(_norm(b.album)) : (a.discNo * 1000 + a.trackNo).compareTo(b.discNo * 1000 + b.trackNo));
    return all;
  }

  List<GhostTrack> _byAlbum(List<GhostTrack> library, String query) {
    final q = _norm(query);
    if (q.length < 3) return const [];
    final tracks = library.where((t) {
      final a = _norm(t.album);
      return a.isNotEmpty && (a == q || _similar(a, q) >= 0.9);
    }).toList();
    tracks.sort((a, b) => (a.discNo * 1000 + a.trackNo).compareTo(b.discNo * 1000 + b.trackNo));
    return tracks;
  }

  List<MapEntry<GhostTrack, double>> _rankTitles(List<GhostTrack> pool, String query) {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    final qTokens = q.split(' ');
    final out = <MapEntry<GhostTrack, double>>[];
    for (final t in pool) {
      final title = _norm(t.title);
      if (title.isEmpty) continue;
      var score = _similar(title, q);
      if (title == q) score = 1.2;
      if (title.contains(q) && q.length >= 3) score = math.max(score, 0.75 + 0.25 * q.length / title.length);
      final tTokens = title.split(' ');
      final overlap = qTokens.where((w) => tTokens.any((x) => x == w || (w.length >= 5 && _distance(w, x) <= 1))).length / qTokens.length;
      score = math.max(score, overlap * 0.9);
      if (score >= 0.5) out.add(MapEntry(t, score));
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  GhostTrack? _bestTitleMatch(String raw, List<GhostTrack> tracks) {
    final ranked = _rankTitles(tracks, raw);
    return ranked.isEmpty ? null : ranked.first.key;
  }

  String _artistOr(GhostTrack t) => t.artist.trim().isEmpty ? 'unknown artist' : t.artist;

  String _pick(List<String> options) => options[_rng.nextInt(options.length)];

  static const Set<String> _stop = {
    'the', 'a', 'an', 'is', 'are', 'to', 'of', 'and', 'or', 'in', 'on', 'it', 'i', 'me', 'my', 'you', 'do', 'does', 'how', 'what', 'why', 'can',
    'with', 'for', 'this', 'that', 'there', 'be', 'get', 'where', 'when', 'please', 'tell', 'about', 'use', 'work', 'thing', 'should', 'would', 'will',
    'no', 'not', 'dont', 'doesnt', 'isnt', 'wont', 'cant', 'any', 'have', 'has', 'am', 'was', 'into', 'from', 'by', 'at', 'as', 'if', 'so', 'just',
  };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[’'`]"), '').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _tokens(String s) {
    final n = _norm(s);
    return n.isEmpty ? <String>[] : n.split(' ');
  }

  static String _stem(String w) {
    if (w.length > 5 && w.endsWith('ing')) return w.substring(0, w.length - 3);
    if (w.length > 4 && w.endsWith('ed')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  static List<String> _terms(String text) => _tokens(text).map((w) => _synonyms[w] ?? w).map(_stem).where((w) => w.length > 1 && !_stop.contains(w)).toList();

  static List<String> _correct(List<String> words) {
    return words.map((w) {
      if (_synonyms.containsKey(w)) return _synonyms[w]!;
      if (w.length < 4 || _vocabulary.contains(w) || RegExp(r'^\d+$').hasMatch(w)) return w;
      String? best;
      var bestDistance = 99;
      final limit = w.length >= 7 ? 2 : 1;
      for (final v in _vocabulary) {
        if ((v.length - w.length).abs() > limit) continue;
        final d = _distance(w, v);
        if (d < bestDistance) {
          bestDistance = d;
          best = v;
        }
      }
      if (best != null && bestDistance <= limit) return _synonyms[best] ?? best;
      return w;
    }).toList();
  }

  static double _similar(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final longest = math.max(a.length, b.length);
    return 1 - _distance(a, b) / longest;
  }

  static int _distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev2 = List<int>.filled(b.length + 1, 0);
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = math.min(v, prev2[j - 2] + 1);
        }
        cur[j] = v;
      }
      final t = prev2;
      prev2 = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }
}
