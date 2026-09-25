// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/lrc.dart';
import '../core/metadata_sources.dart';

Future<Map<String, String>?> showMetadataReview({
  required BuildContext context,
  required Map<String, String> current,
  required List<MetaCandidate> candidates,
  required Color themeColor,
  String lyricsPlain = '',
  String lyricsSynced = '',
  double confidence = 0,
  String heading = 'REVIEW MATCH',
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MetadataReviewSheet(
      current: current,
      candidates: candidates,
      themeColor: themeColor,
      lyricsPlain: lyricsPlain,
      lyricsSynced: lyricsSynced,
      confidence: confidence,
      heading: heading,
    ),
  );
}

class _MetadataReviewSheet extends StatefulWidget {
  final Map<String, String> current;
  final List<MetaCandidate> candidates;
  final Color themeColor;
  final String lyricsPlain;
  final String lyricsSynced;
  final double confidence;
  final String heading;

  const _MetadataReviewSheet({
    required this.current,
    required this.candidates,
    required this.themeColor,
    required this.lyricsPlain,
    required this.lyricsSynced,
    required this.confidence,
    required this.heading,
  });

  @override
  State<_MetadataReviewSheet> createState() => _MetadataReviewSheetState();
}

class _MetadataReviewSheetState extends State<_MetadataReviewSheet> {
  static const List<(String, String)> _fields = [
    ('TITLE', 'TITLE'),
    ('ARTIST', 'ARTIST'),
    ('ALBUM', 'ALBUM'),
    ('ALBUM_ARTIST', 'ALBUM ARTIST'),
    ('YEAR', 'YEAR'),
    ('GENRE', 'GENRE'),
    ('TRACK', 'TRACK NO.'),
    ('TRACK_TOTAL', 'TRACK TOTAL'),
    ('DISC_NO', 'DISC NO.'),
    ('DISC_TOTAL', 'DISC TOTAL'),
  ];

  int _selected = 0;
  Map<String, String> _proposal = {};
  final Map<String, bool> _checked = {};
  final Map<String, String?> _artCache = {};
  bool _artLoading = false;
  bool _useArt = false;
  String _lyricsChoice = 'keep';

  @override
  void initState() {
    super.initState();
    final currentLyrics = widget.current['LYRICS'] ?? '';
    if (widget.lyricsSynced.isNotEmpty && (currentLyrics.trim().isEmpty || !Lrc.isSynced(currentLyrics))) {
      _lyricsChoice = 'synced';
    } else if (widget.lyricsPlain.isNotEmpty && currentLyrics.trim().isEmpty) {
      _lyricsChoice = 'plain';
    }
    if (widget.candidates.isNotEmpty) _select(0);
  }

  String _cur(String key) => (widget.current[key] ?? '').trim();

  void _select(int index) {
    _selected = index;
    _proposal = widget.candidates[index].toTags();
    _checked.clear();
    for (final (key, _) in _fields) {
      final p = (_proposal[key] ?? '').trim();
      _checked[key] = p.isNotEmpty && p != _cur(key);
    }
    final url = widget.candidates[index].artworkUrl;
    _useArt = url.isNotEmpty;
    if (url.isNotEmpty && !_artCache.containsKey(url)) {
      _artLoading = true;
      MetadataSources.fetchArtworkBase64(url).then((b64) {
        if (!mounted) return;
        setState(() {
          _artCache[url] = b64;
          _artLoading = false;
          if (b64 == null && widget.candidates[_selected].artworkUrl == url) _useArt = false;
        });
      });
    }
  }

  void _fillEmptyOnly() {
    setState(() {
      for (final (key, _) in _fields) {
        final p = (_proposal[key] ?? '').trim();
        _checked[key] = p.isNotEmpty && _cur(key).isEmpty;
      }
      _useArt = _proposedArt != null && _cur('ARTWORK_BASE64').isEmpty;
      if (_cur('LYRICS').isNotEmpty) _lyricsChoice = 'keep';
    });
  }

  void _selectAll() {
    setState(() {
      for (final (key, _) in _fields) {
        final p = (_proposal[key] ?? '').trim();
        _checked[key] = p.isNotEmpty && p != _cur(key);
      }
      _useArt = _proposedArt != null;
    });
  }

  String? get _proposedArt {
    if (widget.candidates.isEmpty) return null;
    final url = widget.candidates[_selected].artworkUrl;
    return url.isEmpty ? null : _artCache[url];
  }

  int get _changeCount {
    var n = _checked.values.where((v) => v).length;
    if (_useArt && _proposedArt != null) n++;
    if (_lyricsChoice != 'keep') n++;
    return n;
  }

  Map<String, String> _result() {
    final out = <String, String>{};
    for (final (key, _) in _fields) {
      if (_checked[key] == true) out[key] = (_proposal[key] ?? '').trim();
    }
    final art = _proposedArt;
    if (_useArt && art != null) out['ARTWORK_BASE64'] = art;
    if (_lyricsChoice == 'synced' && widget.lyricsSynced.isNotEmpty) out['LYRICS'] = widget.lyricsSynced;
    if (_lyricsChoice == 'plain' && widget.lyricsPlain.isNotEmpty) out['LYRICS'] = widget.lyricsPlain;
    return out;
  }

  Widget _thumb(String? b64, Color border) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: border)),
      child: b64 == null || b64.isEmpty
          ? const Icon(Icons.image_not_supported, color: Colors.white24)
          : Image.memory(base64Decode(b64), fit: BoxFit.cover, gaplessPlayback: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.themeColor;
    final pct = (widget.confidence * 100).clamp(0, 100).round();
    final confColor = widget.confidence >= 0.85 ? Colors.greenAccent : (widget.confidence >= 0.65 ? Colors.amberAccent : Colors.redAccent);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scroll) => Material(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: c.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 10, bottom: 6), height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(widget.heading, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: c))),
                  if (widget.candidates.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(border: Border.all(color: confColor), borderRadius: BorderRadius.circular(4)),
                      child: Text("MATCH $pct%", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: confColor)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  if (widget.candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("> NO CATALOG MATCH. ONLY LYRICS ARE AVAILABLE BELOW.", style: TextStyle(fontFamily: 'VT323', fontSize: 16, color: Colors.white54)),
                    ),
                  if (widget.candidates.isNotEmpty) ...[
                    const Text("CANDIDATES", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.candidates.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final cand = widget.candidates[i];
                          final active = i == _selected;
                          return InkWell(
                            onTap: () => setState(() => _select(i)),
                            child: Container(
                              width: 200,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: active ? c.withValues(alpha: 0.12) : Colors.black,
                                border: Border.all(color: active ? c : Colors.white24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${cand.artist} — ${cand.title}", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: active ? c : Colors.white, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(cand.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                                  const Spacer(),
                                  Text("${cand.source.toUpperCase()} • ${(cand.score.clamp(0, 1) * 100).round()}%", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: _fillEmptyOnly, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)), child: const Text("FILL EMPTY ONLY", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)))),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton(onPressed: _selectAll, style: OutlinedButton.styleFrom(side: BorderSide(color: c.withValues(alpha: 0.5))), child: Text("REPLACE ALL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: c)))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _useArt && _proposedArt != null,
                          activeColor: c,
                          onChanged: _proposedArt == null ? null : (v) => setState(() => _useArt = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const SizedBox(width: 70, child: Text("ARTWORK", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70))),
                        _thumb(_cur('ARTWORK_BASE64'), Colors.white24),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 16, color: Colors.white38)),
                        _artLoading ? SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: c))) : _thumb(_proposedArt, c),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    for (final (key, label) in _fields) _fieldRow(key, label, c),
                  ],
                  if (widget.lyricsPlain.isNotEmpty || widget.lyricsSynced.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    const Text("LYRICS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.lyricsSynced.isNotEmpty) _lyricsChip('synced', 'SYNCED (KARAOKE)', c),
                        if (widget.lyricsPlain.isNotEmpty) _lyricsChip('plain', 'PLAIN TEXT', c),
                        _lyricsChip('keep', _cur('LYRICS').isEmpty ? 'NONE' : 'KEEP CURRENT', c),
                      ],
                    ),
                    if (_lyricsChoice != 'keep')
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(maxHeight: 140),
                        decoration: BoxDecoration(border: Border.all(color: Colors.white12)),
                        child: SingleChildScrollView(
                          child: Text(
                            _lyricsChoice == 'synced' ? widget.lyricsSynced : widget.lyricsPlain,
                            style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.2),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _changeCount == 0 ? null : () => Navigator.pop(context, _result()),
                        icon: const Icon(Icons.check, color: Colors.black),
                        label: Text("APPLY $_changeCount TO FORM", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: c, disabledBackgroundColor: c.withValues(alpha: 0.2), padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lyricsChip(String value, String label, Color c) {
    final active = _lyricsChoice == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: active ? Colors.black : Colors.white70)),
      selected: active,
      selectedColor: c,
      backgroundColor: Colors.black,
      side: BorderSide(color: active ? c : Colors.white24),
      showCheckmark: false,
      onSelected: (_) => setState(() => _lyricsChoice = value),
    );
  }

  Widget _fieldRow(String key, String label, Color c) {
    final cur = _cur(key);
    final prop = (_proposal[key] ?? '').trim();
    final changed = prop.isNotEmpty && prop != cur;
    final on = _checked[key] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(value: on, activeColor: c, onChanged: prop.isEmpty ? null : (v) => setState(() => _checked[key] = v ?? false)),
          const SizedBox(width: 4),
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cur.isEmpty ? '—' : cur,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'ShareTechMono',
                    fontSize: 12,
                    color: on && changed ? Colors.white38 : Colors.white,
                    decoration: on && changed && cur.isNotEmpty ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (changed)
                  Text("→ $prop", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: on ? c : Colors.white38, fontWeight: on ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
