// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;

class GhostClassifier {
  static const double _threshold = 0.14;
  static const List<String> intents = [
    'GRABBER',
    'FORGE',
    'PIPELINE',
    'WORKBENCH',
    'LIBRARY',
    'PLAYER',
    'SETTINGS',
    'WHISPER',
    'EQ',
    'REPLAYGAIN',
    'CROSSFADE',
    'GAPLESS',
    'BACKUP',
    'WIDGET',
    'GENERAL',
  ];

  static const Map<String, List<String>> _corpora = {
    'GRABBER': [
      'how do i download from youtube',
      'search for music',
      'download video as mp3',
      'what formats are available',
      'merge video and audio',
      'facebook video no audio',
      'source copy vs mp3 320k',
      'download playlist',
      'best quality download',
      'how to use grabber',
      'search not working',
      'format selection',
      'composite formats vid aud',
      'self heal silent video',
      'cancel download',
      'quick video 1080p',
      'extract audio only',
      'download to music folder',
      'best audio format',
      'retry failed download',
    ],
    'FORGE': [
      'edit id3 tags',
      'change song title',
      'change artist name',
      'album art',
      'change album name',
      'year tag',
      'genre tag',
      'track number',
      'lyrics tag',
      'export preserves container',
      'mp3 export',
      'flac export',
      'write readback verify',
      'eject media cache only',
      'karaoke mode',
      'lyric sync screen',
      'lrc sidecar',
      'staging copy purged',
      'tag editing',
      'auto fetch metadata',
    ],
    'PIPELINE': [
      'batch process',
      'ghost partial pristine processed failed',
      'acrcloud identify',
      'genius spider',
      'itunes fallback',
      'musicbrainz',
      'cancel batch',
      'retry failed',
      'mixtape join',
      'lossless concat',
      'batch running flag',
      'per item retry',
      'pipeline buckets',
      'fingerprint',
      'metadata enrichment',
      'file picker multiple',
      'mounted guards',
      'wav cleanup',
    ],
    'WORKBENCH': [
      'dsp effects',
      'normalize lufs -14',
      'two pass loudnorm',
      'scan lufs',
      'apply fades',
      'fold to mono',
      'trim silence',
      'speed pitch',
      'varispeed rubberband atempo',
      'reverb aecho',
      'ai denoise afftdn',
      'parametric eq 5 band',
      '15 band eq autoeq',
      'compress dynamics acompressor',
      'replaygain scan txxx',
      'whisper transcribe',
      'pcm lossless 48k 16bit',
      'bit depth sample rate soxr',
      'clip media hh mm ss',
      'extract audio convert format',
    ],
    'LIBRARY': [
      'browse mediastore',
      'by album',
      'by artist',
      'by folder',
      'search library',
      'filter realtime',
      'play track',
      'replace queue',
      'album view',
      'artist view',
      'search filter',
      'mediastore scan',
      'file picker',
      'browse library scan',
    ],
    'PLAYER': [
      'play pause next previous seek',
      'shuffle repeat off all one',
      'speed 0.5x 2x sleep timer',
      'crossfade 0 12s gapless',
      'concatenating audio source',
      'queue persist restore',
      'mini player theater mode',
      'pinch zoom artwork',
      'lockscreen controls',
      'media button receiver',
      'wake lock',
      'lyrics panel lrc auto scroll',
      'move after current add to queue',
      'reorder remove clear queue',
      'edge to edge swipe',
    ],
    'SETTINGS': [
      'genius api key',
      'acrcloud host access key secret',
      'save keys xor 0x53 export config',
      'yt dlp update scorched earth',
      'full stack refresh',
      'python doctor patch registry',
      'ffmpeg probe whisper docs',
      'cache purge',
      'accent color picker',
      '15 band eq presets',
      'playback engine crossfade gapless',
      'ghost tutorial',
      'reduce motion global',
      'auto expand ghost visible',
      'backup restore',
    ],
    'WHISPER': [
      'transcribe audio whisper ai',
      'ggml base en 141mb model',
      'model extraction srt sidecar',
      'language en auto',
      'cpu heavy real time',
      'whisper filter destination srt',
      'on device docs filter syntax',
      'self diagnosing',
    ],
    'EQ': [
      '15 band equalizer autoeq',
      '25hz 16khz q 1.2 purple',
      'save preset flat',
      'bass 100hz lowmid 320hz mid 1khz',
      'highmid 3.5khz treble 8khz',
      'parametric eq 5 band',
      'workbench settings sync',
    ],
    'REPLAYGAIN': [
      'replaygain scan ebu r128',
      'integrated loudness true peak',
      'track gain track peak album gain album peak',
      'target -14 lufs txxx frames',
      'id3 channel jaudiotagger',
      'scan lufs button',
    ],
    'CROSSFADE': [
      'crossfade 0 12s acrossfade filter',
      'theater toggle',
      'settings cyan gapless toggle',
      'concatenating audio source zero silence',
    ],
    'GAPLESS': [
      'gapless audit test tones 440hz 880hz',
      'rms gap measurement',
      'verify zero silence',
      'run gapless audit pass fail',
    ],
    'BACKUP': [
      'backup all restore all xor 0x53',
      'encrypted json settings eq presets',
      'persist queue shared preferences',
      'export config bin downloads',
    ],
    'WIDGET': [
      'home screen widget remoteviews',
      'prev play next queue 4 button',
      'sovereign widget provider appwidget',
      'min width 250dp min height 180dp',
    ],
    'GENERAL': [
      'help about first launch welcome to the machine',
      'skynet just kidding hahaha ghost tutorial',
      'how to use what is this overview features tutorial',
      'ghost personality sarcastic happy serious glitch laugh',
    ],
  };

  static const Set<String> _stopwords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'can', 'this', 'that', 'these', 'those',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'what', 'which', 'who',
    'when', 'where', 'why', 'how', 'my', 'your', 'his', 'her', 'its',
    'our', 'their', 'me', 'him', 'us', 'them',
  };

  final Map<String, double> _idf = {};
  final Map<String, Map<String, double>> _centroids = {};
  final Map<String, double> _centroidNorms = {};
  bool _ready = false;

  bool get isReady => _ready;

  GhostClassifier() {
    _build();
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1 && !_stopwords.contains(t))
        .toList();
  }

  void _build() {
    final int n = intents.length;
    final Map<String, int> df = {};
    final Map<String, List<String>> tokenizedCorpora = {};

    for (final intent in intents) {
      final phrases = _corpora[intent] ?? [];
      final tokens = phrases.expand(_tokenize).toList();
      tokenizedCorpora[intent] = tokens;
      final unique = tokens.toSet();
      for (final term in unique) {
        df[term] = (df[term] ?? 0) + 1;
      }
    }

    for (final entry in df.entries) {
      _idf[entry.key] = math.log(n / (entry.value + 1)) + 1;
    }

    for (final intent in intents) {
      final tokens = tokenizedCorpora[intent] ?? [];
      if (tokens.isEmpty) continue;
      final tf = <String, int>{};
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      final total = tokens.length.toDouble();
      final vec = <String, double>{};
      double sumSq = 0;
      for (final e in tf.entries) {
        final w = (e.value / total) * (_idf[e.key] ?? 1.0);
        vec[e.key] = w;
        sumSq += w * w;
      }
      _centroids[intent] = vec;
      _centroidNorms[intent] = math.sqrt(sumSq);
    }

    _ready = true;
  }

  String? classify(String query) {
    if (!_ready) return null;
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return null;

    final tf = <String, int>{};
    for (final t in tokens) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final total = tokens.length.toDouble();
    final qvec = <String, double>{};
    double qSumSq = 0;
    for (final e in tf.entries) {
      final idf = _idf[e.key];
      if (idf == null) continue;
      final w = (e.value / total) * idf;
      qvec[e.key] = w;
      qSumSq += w * w;
    }
    if (qvec.isEmpty) return null;
    final qNorm = math.sqrt(qSumSq);
    if (qNorm == 0) return null;

    String? bestIntent;
    double bestScore = 0;
    for (final intent in intents) {
      final cvec = _centroids[intent];
      final cNorm = _centroidNorms[intent] ?? 1.0;
      if (cvec == null || cNorm == 0) continue;
      double dot = 0;
      for (final e in qvec.entries) {
        final cv = cvec[e.key];
        if (cv != null) dot += e.value * cv;
      }
      final score = dot / (qNorm * cNorm);
      if (score > bestScore) {
        bestScore = score;
        bestIntent = intent;
      }
    }

    if (bestIntent != null && bestScore >= _threshold) return bestIntent;
    return null;
  }
}
