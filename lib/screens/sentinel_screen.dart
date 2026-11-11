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
  List<SentinelHit> _hits = [];
  SentinelScanSummary? _summary;
  SentinelProgress? _progress;
  bool _scanning = false;
  bool _resumeAvailable = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadHits();
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        final high = _hits.where((h) => h.severity == 'high').length;
        final medium = _hits.where((h) => h.severity == 'medium').length;
        final low = _hits.where((h) => h.severity == 'low').length;
        final issueCounts = <String, int>{};
        for (final hit in _hits) {
          for (final issue in hit.issues) {
            issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
          }
        }
        final topIssues = issueCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text('SENTINEL', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            iconTheme: IconThemeData(color: themeColor),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${_hits.length} HITS  •  HIGH $high  •  MED $medium  •  LOW $low', style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70))),
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
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
              Divider(color: themeColor.withValues(alpha: 0.2), height: 1),
              Expanded(
                child: _hits.isEmpty
                    ? Center(child: Text(_summary == null ? 'NO HITS YET — RUN A SCAN.' : 'NO HITS — LIBRARY IS CLEAN.', style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38)))
                    : ListView.builder(
                        itemCount: _hits.length,
                        itemBuilder: (context, index) {
                          final hit = _hits[index];
                          final sevColor = hit.severity == 'high' ? Colors.redAccent : (hit.severity == 'medium' ? Colors.amber : Colors.white54);
                          return Container(
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(hit.displayName, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text('→ ${hit.expectedName}', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                                const SizedBox(height: 2),
                                Text(hit.issues.join(', '), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(hit.severity.toUpperCase(), style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: sevColor, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => _openInForge(hit),
                                      child: Text('OPEN IN FORGE', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
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
