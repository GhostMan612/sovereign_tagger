// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import '../core/forge_request.dart';
import '../core/sentinel_scanner.dart';
import '../services/sentinel_store.dart';
import 'main_shell.dart';

class SentinelScreen extends StatefulWidget {
  const SentinelScreen({super.key});

  @override
  State<SentinelScreen> createState() => _SentinelScreenState();
}

class _SentinelScreenState extends State<SentinelScreen> {
  final SentinelScanner _scanner = SentinelScanner();
  final SentinelStore _store = SentinelStore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  List<SentinelHit> _hits = [];
  SentinelScanSummary? _summary;
  SentinelProgress? _progress;
  bool _scanning = false;
  bool _rescanOneRunning = false;
  bool _resumeAvailable = false;
  String _status = '';
  String _filterStatus = 'all';
  String _filterSeverity = 'all';
  String _filterIssue = 'all';
  String _search = '';
  bool _groupByAlbum = false;
  bool _filterMigration = false;
  final Set<String> _selected = <String>{};
  final Set<String> _collapsedGroups = <String>{};

  static const Map<String, String> _statusLabels = {
    'all': 'ALL',
    'open': 'OPEN',
    'in_forge': 'IN FORGE',
    'in_pipeline': 'IN PIPELINE',
    'resolved': 'RESOLVED',
    'ignored': 'IGNORED',
    'uncompletable': 'UNCOMPLETABLE',
    'stale': 'STALE',
  };

  static const List<String> _statusOrder = ['all', 'open', 'in_forge', 'in_pipeline', 'resolved', 'ignored', 'uncompletable', 'stale'];

  static const Map<String, String> _severityLabels = {
    'all': 'ALL',
    'high': 'HIGH',
    'medium': 'MEDIUM',
    'low': 'LOW',
  };

  @override
  void initState() {
    super.initState();
    _loadHits();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SentinelHit> get _visibleHits {
    final q = _search.trim().toLowerCase();
    final filtered = _hits.where((h) {
      if (_filterMigration) {
        if (!h.issues.contains(SentinelIssue.nameMismatch)) return false;
        if (h.issues.contains(SentinelIssue.nameCollision)) return false;
        if (h.status != SentinelStatus.open && h.status != SentinelStatus.inForge && h.status != SentinelStatus.inPipeline) return false;
      }
      if (_filterStatus != 'all' && h.status != _filterStatus) return false;
      if (_filterSeverity != 'all' && h.severity != _filterSeverity) return false;
      if (_filterIssue != 'all' && !h.issues.contains(_filterIssue)) return false;
      if (q.isNotEmpty) {
        final hay = '${h.displayName} ${h.tagSnapshot.artist} ${h.tagSnapshot.album}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) {
      final rank = {'high': 0, 'medium': 1, 'low': 2};
      final ra = rank[a.severity] ?? 3;
      final rb = rank[b.severity] ?? 3;
      if (ra != rb) return ra.compareTo(rb);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return filtered;
  }

  String _albumKey(SentinelHit h) {
    final album = h.tagSnapshot.album.trim();
    if (album.isEmpty) return 'NO ALBUM';
    final artist = h.tagSnapshot.albumArtist.trim();
    return artist.isEmpty ? album : '$artist — $album';
  }

  int _worstRank(List<SentinelHit> hits) {
    var worst = 3;
    for (final h in hits) {
      final r = {'high': 0, 'medium': 1, 'low': 2}[h.severity] ?? 3;
      if (r < worst) worst = r;
    }
    return worst;
  }

  Map<String, List<SentinelHit>> get _albumGroups {
    final groups = <String, List<SentinelHit>>{};
    for (final hit in _visibleHits) {
      groups.putIfAbsent(_albumKey(hit), () => []).add(hit);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ra = _worstRank(groups[a]!);
        final rb = _worstRank(groups[b]!);
        if (ra != rb) return ra.compareTo(rb);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final k in keys) k: groups[k]!};
  }

  List<_ListEntry> get _groupedEntries {
    final entries = <_ListEntry>[];
    for (final entry in _albumGroups.entries) {
      entries.add(_GroupEntry(entry.key, entry.value));
      if (!_collapsedGroups.contains(entry.key)) {
        for (final hit in entry.value) entries.add(_HitEntry(hit));
      }
    }
    return entries;
  }

  Future<void> _loadHits() async {
    await _scanner.store.ensureLoaded();
    if (!mounted) return;
    final hits = List<SentinelHit>.of(_scanner.store.allHits);
    hits.sort((a, b) {
      final rank = {'high': 0, 'medium': 1, 'low': 2};
      final ra = rank[a.severity] ?? 3;
      final rb = rank[b.severity] ?? 3;
      if (ra != rb) return ra.compareTo(rb);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    setState(() {
      _hits = hits;
      _selected.removeWhere((id) => !_hits.any((h) => h.id == id));
      _resumeAvailable = (_scanner.store.scanProgress?.pendingUris.isNotEmpty ?? false);
    });
  }

  Future<void> _runScan({bool fullRescan = false, bool resume = false}) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _progress = null;
      _status = 'SCANNING LIBRARY...';
    });
    try {
      final summary = await _scanner.run(
        fullRescan: fullRescan,
        resume: resume,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _status = 'SCAN ${summary.status.toUpperCase()}: ${summary.scanned} SCANNED, ${summary.hits} HITS, ${summary.sampleSize} SAMPLED (${summary.sampleHits} SAMPLE HITS)';
      });
      await _loadHits();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'ERR: SCAN FAILED: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openInForge(SentinelHit hit) async {
    if (hit.path.isEmpty) {
      setState(() => _status = 'ERR: NO FILE PATH — CANNOT OPEN IN FORGE');
      return;
    }
    await _scanner.store.setStatus(hit.id, 'in_forge', 'Opened in Forge');
    SovereignState.sendToForge(ForgeRequest(
      path: hit.path,
      origin: ForgeOrigin.library,
      originUri: hit.uri.isEmpty ? null : hit.uri,
      suggestedFileName: hit.expectedName,
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _hitAction(String action, SentinelHit hit) async {
    switch (action) {
      case 'forge':
        await _openInForge(hit);
      case 'pipeline':
        await _sendToPipeline([hit]);
      case 'rescan':
        await _rescanOne(hit);
      case 'ignore':
        await _ignore([hit]);
      case 'uncompletable':
        await _markUncompletable([hit]);
      case 'reopen':
        await _reopen([hit]);
    }
  }

  Future<void> _sendToPipeline(List<SentinelHit> hits) async {
    final targets = hits.where((h) => h.path.isNotEmpty).toList();
    if (targets.isEmpty) {
      setState(() => _status = 'ERR: NO FILE PATHS — NOTHING TO SEND TO PIPELINE');
      return;
    }
    setState(() => _status = 'SENDING ${targets.length} TO PIPELINE...');
    try {
      final sent = await _store.sentinelSendToPipeline(targets.map((h) => h.id).toList());
      if (!mounted) return;
      if (sent == 0) {
        setState(() => _status = 'ERR: PIPELINE HANDOFF NOT AVAILABLE — OPEN THE PIPELINE TAB ONCE, THEN RETRY');
      } else {
        setState(() {
          _status = 'SENT $sent TO PIPELINE — OPEN THE PIPELINE TAB TO RUN THE BATCH';
          _selected.removeWhere((id) => targets.any((h) => h.id == id));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'ERR: SEND TO PIPELINE FAILED: $e');
    }
    await _loadHits();
  }

  Future<void> _sendToForge(List<SentinelHit> hits) async {
    final targets = hits.where((h) => h.path.isNotEmpty).toList();
    if (targets.isEmpty) {
      setState(() => _status = 'ERR: NO FILE PATHS — NOTHING TO SEND TO FORGE');
      return;
    }
    for (final hit in targets) {
      await _store.setStatus(hit.id, SentinelStatus.inForge, 'Queued to Forge');
    }
    SovereignState.queueToForge([
      for (final hit in targets)
        ForgeRequest(
          path: hit.path,
          origin: ForgeOrigin.library,
          originUri: hit.uri.isEmpty ? null : hit.uri,
          suggestedFileName: hit.expectedName,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      _status = 'QUEUED ${targets.length} TO FORGE — FIRST FILE MOUNTED; EJECT IN FORGE TO ADVANCE THE QUEUE';
      _selected.removeWhere((id) => targets.any((h) => h.id == id));
    });
    await _loadHits();
  }

  Future<String?> _askReason({required String title, required String hint}) async {
    final ctrl = TextEditingController();
    final themeColor = SovereignState.accentColor.value;
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(side: BorderSide(color: themeColor), borderRadius: BorderRadius.circular(6)),
        title: Text(title, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('CANCEL', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(d, ctrl.text.trim()),
            child: const Text('CONFIRM', style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _ignore(List<SentinelHit> hits) async {
    final reason = await _askReason(title: 'IGNORE ${hits.length} HIT${hits.length == 1 ? '' : 'S'}', hint: 'REASON (OPTIONAL)');
    if (reason == null) return;
    for (final hit in hits) {
      await _store.sentinelIgnore(hit.id, reason);
    }
    if (!mounted) return;
    setState(() {
      _status = 'IGNORED ${hits.length} HIT${hits.length == 1 ? '' : 'S'} — REOPEN ANYTIME FROM THE HIT MENU';
      _selected.removeWhere((id) => hits.any((h) => h.id == id));
    });
    await _loadHits();
  }

  Future<void> _markUncompletable(List<SentinelHit> hits) async {
    var choice = SentinelUncompletableReason.noCatalogMatch;
    final noteCtrl = TextEditingController();
    final themeColor = SovereignState.accentColor.value;
    const reasons = [SentinelUncompletableReason.noCatalogMatch, SentinelUncompletableReason.noLyricsSource, SentinelUncompletableReason.noArtworkSource];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialogState) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(side: BorderSide(color: themeColor), borderRadius: BorderRadius.circular(6)),
          title: Text('MARK ${hits.length} UNCOMPLETABLE', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reason in reasons)
                RadioListTile<String>(
                  title: Text(reason, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 12)),
                  value: reason,
                  groupValue: choice,
                  activeColor: themeColor,
                  onChanged: (v) => setDialogState(() => choice = v!),
                ),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'OPTIONAL NOTE (OVERRIDES THE REASON ABOVE)',
                  hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('CANCEL', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('CONFIRM', style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirmed != true) return;
    final reason = note.isNotEmpty ? note : choice;
    for (final hit in hits) {
      await _store.sentinelMarkUncompletable(hit.id, reason);
    }
    if (!mounted) return;
    setState(() {
      _status = 'MARKED ${hits.length} UNCOMPLETABLE ($reason) — NOT RE-FLAGGED UNTIL THE FILE CHANGES';
      _selected.removeWhere((id) => hits.any((h) => h.id == id));
    });
    await _loadHits();
  }

  Future<void> _reopen(List<SentinelHit> hits) async {
    for (final hit in hits) {
      await _store.setStatus(hit.id, SentinelStatus.open, 'Reopened by operator');
    }
    if (!mounted) return;
    setState(() {
      _status = 'REOPENED ${hits.length} HIT${hits.length == 1 ? '' : 'S'}';
      _selected.removeWhere((id) => hits.any((h) => h.id == id));
    });
    await _loadHits();
  }

  Future<void> _rescanOne(SentinelHit hit) async {
    if (_scanning || _rescanOneRunning) return;
    setState(() {
      _rescanOneRunning = true;
      _status = 'RESCANNING ${hit.displayName}...';
    });
    try {
      final updated = await _scanner.rescanOne(hit);
      if (!mounted) return;
      if (updated == null) {
        setState(() => _status = 'ERR: HIT NO LONGER IN STORE');
      } else if (updated.issues.isEmpty) {
        setState(() => _status = 'RESCAN: ${updated.displayName} IS CLEAN NOW — MARKED ${updated.status.toUpperCase()}');
      } else {
        setState(() => _status = 'RESCAN: ${updated.displayName} — ${updated.issues.length} ISSUE${updated.issues.length == 1 ? '' : 'S'} (${updated.status.toUpperCase()})');
      }
      await _loadHits();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'ERR: RESCAN FAILED: $e');
    } finally {
      if (mounted) setState(() => _rescanOneRunning = false);
    }
  }

  List<String> get _issueOptions {
    final codes = <String>{};
    for (final hit in _hits) {
      codes.addAll(hit.issues);
    }
    final sorted = codes.toList()..sort();
    return ['all', ...sorted];
  }

  List<SentinelHit> _selectedHits() => _hits.where((h) => _selected.contains(h.id)).toList();

  Widget _chipRow(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in _statusOrder)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_statusLabels[status]!, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
                  selected: _filterStatus == status,
                  selectedColor: themeColor,
                  backgroundColor: Colors.white12,
                  labelStyle: TextStyle(color: _filterStatus == status ? Colors.black : Colors.white70),
                  onSelected: (_) => setState(() => _filterStatus = status),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _severityRow(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in _severityLabels.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.value, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
                  selected: _filterSeverity == entry.key,
                  selectedColor: themeColor,
                  backgroundColor: Colors.white12,
                  labelStyle: TextStyle(color: _filterSeverity == entry.key ? Colors.black : Colors.white70),
                  onSelected: (_) => setState(() => _filterSeverity = entry.key),
                ),
              ),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: _issueOptions.contains(_filterIssue) ? _filterIssue : 'all',
              dropdownColor: Colors.black,
              style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70),
              underline: Container(height: 1, color: themeColor.withValues(alpha: 0.4)),
              items: [
                for (final code in _issueOptions)
                  DropdownMenuItem(value: code, child: Text(code == 'all' ? 'ALL ISSUES' : code, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11))),
              ],
              onChanged: (v) => setState(() => _filterIssue = v ?? 'all'),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('GROUP BY ALBUM', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
              selected: _groupByAlbum,
              selectedColor: themeColor,
              backgroundColor: Colors.white12,
              labelStyle: TextStyle(color: _groupByAlbum ? Colors.black : Colors.white70),
              onSelected: (_) => setState(() => _groupByAlbum = !_groupByAlbum),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('MIGRATION', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
              selected: _filterMigration,
              selectedColor: themeColor,
              backgroundColor: Colors.white12,
              labelStyle: TextStyle(color: _filterMigration ? Colors.black : Colors.white70),
              onSelected: (_) => setState(() => _filterMigration = !_filterMigration),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(Color themeColor) {
    final selected = _selectedHits();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.12), border: Border(top: BorderSide(color: themeColor.withValues(alpha: 0.3)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${selected.length} SELECTED', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _selButton(themeColor, 'SEND TO FORGE', () => _sendToForge(selected)),
              _selButton(themeColor, 'SEND TO PIPELINE', () => _sendToPipeline(selected)),
              _selButton(themeColor, 'IGNORE', () => _ignore(selected)),
              _selButton(themeColor, 'UNCOMPLETABLE', () => _markUncompletable(selected)),
              _selButton(themeColor, 'REOPEN', () => _reopen(selected)),
              _selButton(themeColor, 'CLEAR', () => setState(() => _selected.clear()), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selButton(Color themeColor, String label, VoidCallback onPressed, {bool danger = false}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: danger ? Colors.redAccent : themeColor),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 30),
      ),
      onPressed: onPressed,
      child: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: danger ? Colors.redAccent : themeColor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _hitRow(SentinelHit hit, Color themeColor) {
    final sevColor = hit.severity == 'high' ? Colors.redAccent : (hit.severity == 'medium' ? Colors.amber : Colors.white54);
    final isSelected = _selected.contains(hit.id);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: isSelected,
            activeColor: themeColor,
            checkColor: Colors.black,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(hit.id);
              } else {
                _selected.remove(hit.id);
              }
            }),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hit.displayName, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('→ ${hit.expectedName}', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                const SizedBox(height: 2),
                Text(hit.issues.join(', '), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(hit.severity.toUpperCase(), style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: sevColor, fontWeight: FontWeight.bold)),
                    if (hit.status != SentinelStatus.open) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${hit.status.toUpperCase()}${hit.statusReason.isEmpty ? '' : ' — ${hit.statusReason}'}',
                          style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white38),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: themeColor),
            color: Colors.black,
            onSelected: (value) => _hitAction(value, hit),
            itemBuilder: (context) => [
              _menuItem('forge', 'OPEN IN FORGE'),
              _menuItem('pipeline', 'SEND TO PIPELINE'),
              _menuItem('rescan', 'RESCAN ONE'),
              _menuItem('ignore', 'IGNORE...'),
              _menuItem('uncompletable', 'MARK UNCOMPLETABLE...'),
              if (hit.status == SentinelStatus.ignored || hit.status == SentinelStatus.uncompletable)
                _menuItem('reopen', 'REOPEN'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Text(label, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 12)),
    );
  }

  Widget _groupHeader(_GroupEntry entry, Color themeColor) {
    final high = entry.hits.where((h) => h.severity == 'high').length;
    final collapsed = _collapsedGroups.contains(entry.key);
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsedGroups.remove(entry.key);
        } else {
          _collapsedGroups.add(entry.key);
        }
      }),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.08), border: Border(bottom: BorderSide(color: themeColor.withValues(alpha: 0.2)))),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, color: themeColor, size: 20),
            const SizedBox(width: 4),
            Expanded(
              child: Text(entry.key, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
            ),
            Text('${entry.hits.length} HIT${entry.hits.length == 1 ? '' : 'S'}${high > 0 ? ' • HIGH $high' : ''}', style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        final visible = _visibleHits;
        final high = visible.where((h) => h.severity == 'high').length;
        final medium = visible.where((h) => h.severity == 'medium').length;
        final low = visible.where((h) => h.severity == 'low').length;
        final issueCounts = <String, int>{};
        for (final hit in visible) {
          for (final issue in hit.issues) {
            issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
          }
        }
        final topIssues = issueCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final entries = _groupByAlbum ? _groupedEntries : null;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text('SENTINEL', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            iconTheme: IconThemeData(color: themeColor),
            actions: [
              TextButton(
                onPressed: _scanning
                    ? null
                    : () => setState(() {
                          if (_selected.length == visible.length && visible.isNotEmpty) {
                            _selected.clear();
                          } else {
                            _selected.addAll(visible.map((h) => h.id));
                          }
                        }),
                child: Text(_selected.length == visible.length && visible.isNotEmpty ? 'DESELECT ALL' : 'SELECT ALL', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${visible.length} SHOWN OF ${_hits.length} HITS  •  HIGH $high  •  MED $medium  •  LOW $low', style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70))),
                  ],
                ),
              ),
              if (topIssues.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    topIssues.take(5).map((e) => '${e.key} ${e.value}').join('  •  '),
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white38),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'SEARCH NAME / ARTIST / ALBUM',
                    hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: themeColor),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              _chipRow(themeColor),
              _severityRow(themeColor),
              if (_filterMigration)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'MIGRATION: OLD-FORM NAMES → POLICY FORM "TT - ALBUM ARTIST · TITLE". RENAMES HAPPEN IN FORGE / PIPELINE ONLY — SENTINEL NEVER RENAMES. IGNORED AND UNCOMPLETABLE FILES ARE NOT LISTED; NAME COLLISIONS NEED A MANUAL FIX FIRST. A FILE THAT MATCHES THE POLICY DROPS OUT ON THE NEXT SCAN.',
                    style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54),
                  ),
                ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(_status, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: _status.startsWith('ERR') ? Colors.redAccent : Colors.white38)),
                ),
              if (_progress != null && _progress!.total > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: LinearProgressIndicator(
                    value: _progress!.scanned / _progress!.total,
                    color: themeColor,
                    backgroundColor: Colors.white12,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
                        onPressed: _scanning ? null : () => _runScan(),
                        child: Text(_scanning ? 'SCANNING...' : 'RUN SCAN', style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)),
                      onPressed: _scanning ? null : () => _runScan(fullRescan: true),
                      child: Text('FULL RESCAN', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                    ),
                    if (_resumeAvailable && !_scanning) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
                        onPressed: () => _runScan(resume: true),
                        child: const Text('RESUME', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
                      ),
                    ],
                    if (_scanning) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                        onPressed: () => _scanner.cancel(),
                        child: const Text('CANCEL', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent)),
                      ),
                    ],
                  ],
                ),
              ),
              if (_selected.isNotEmpty) _selectionBar(themeColor),
              Divider(color: themeColor.withValues(alpha: 0.2), height: 1),
              Expanded(
                child: visible.isEmpty
                    ? Center(child: Text(_summary == null && _hits.isEmpty ? 'NO HITS YET — RUN A SCAN.' : 'NO HITS MATCH THE FILTERS.', style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38)))
                    : ListView.builder(
                        itemCount: entries?.length ?? visible.length,
                        itemBuilder: (context, index) {
                          if (entries != null) {
                            final entry = entries[index];
                            if (entry is _GroupEntry) return _groupHeader(entry, themeColor);
                            return _hitRow((entry as _HitEntry).hit, themeColor);
                          }
                          return _hitRow(visible[index], themeColor);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

abstract class _ListEntry {}

class _GroupEntry implements _ListEntry {
  final String key;
  final List<SentinelHit> hits;
  _GroupEntry(this.key, this.hits);
}

class _HitEntry implements _ListEntry {
  final SentinelHit hit;
  _HitEntry(this.hit);
}
