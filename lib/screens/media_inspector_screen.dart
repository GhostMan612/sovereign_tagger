// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/cyber_tap_feedback.dart';
import '../core/forge_request.dart';
import '../core/media_forensics.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../core/tap_feedback.dart';
import '../widgets/cyber_backdrop.dart';
import '../widgets/machine_rain.dart';
import 'main_shell.dart';

enum _InspectorTab { tree, text, json, forensics }

class MediaInspectorScreen extends StatefulWidget {
  final String? initialPath;
  final String? titleHint;
  final bool autoRunForensics;

  const MediaInspectorScreen({
    super.key,
    this.initialPath,
    this.titleHint,
    this.autoRunForensics = false,
  });

  @override
  State<MediaInspectorScreen> createState() => _MediaInspectorScreenState();
}

class _MediaInspectorScreenState extends State<MediaInspectorScreen> {
  _InspectorTab _tab = _InspectorTab.tree;
  MediaInspectionReport? _report;
  ForensicAuditReport? _audit;
  String? _spectrogramPath;
  bool _loading = false;
  bool _auditing = false;
  bool _renderingSpec = false;
  bool _runningSurgery = false;
  String _statusMessage = 'Mount any audio or video file to inspect container atoms, streams, tags, and forensics.';

  @override
  void initState() {
    super.initState();
    final initPath = widget.initialPath?.trim() ?? '';
    if (initPath.isNotEmpty) {
      if (widget.autoRunForensics) {
        _tab = _InspectorTab.forensics;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inspectPath(initPath, autoForensics: widget.autoRunForensics);
      });
    }
  }

  @override
  void dispose() {
    _deleteTempSpectrogram(_spectrogramPath);
    super.dispose();
  }

  void _deleteTempSpectrogram(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _pickAndInspect() async {
    if (_loading || _auditing || _runningSurgery) return;
    TapFeedback.machineTap();
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (!mounted) return;
      if (file == null || file.path == null || file.path!.isEmpty) return;
      await _inspectPath(file.path!);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'ERR: File Picker Fault: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'ERR: File Picker Fault: $e');
    }
  }

  Future<void> _inspectPath(String path, {bool autoForensics = false}) async {
    final prevSpec = _spectrogramPath;
    setState(() {
      _loading = true;
      _audit = null;
      _spectrogramPath = null;
      _statusMessage = 'PROBING CONTAINER & STREAM HEADERS...';
    });
    _deleteTempSpectrogram(prevSpec);

    try {
      final report = await MediaForensics.inspect(path);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _statusMessage =
            'PROBED: ${report.fileName} • ${report.streams.length} STREAM(S)${report.chapters.isEmpty ? '' : ' • ${report.chapters.length} CHAPTER(S)'}';
      });
      if (autoForensics && report.primaryAudio != null) {
        await _runForensics();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'ERR: Probe Failed: $e';
      });
    }
  }

  Future<void> _runForensics() async {
    final report = _report;
    if (report == null || _auditing || _loading) return;
    TapFeedback.machineTap();
    setState(() {
      _auditing = true;
      _statusMessage = 'RUNNING FFMPEG BITSTREAM & SPECTRAL SHELF AUDIT...';
    });
    try {
      final res = await MediaForensics.runDeepAudioAudit(
        report,
        onStage: (stage) {
          if (!mounted) return;
          setState(() => _statusMessage = stage);
        },
      );
      if (!mounted) return;
      TapFeedback.machineConfirm();
      setState(() {
        _audit = res;
        _auditing = false;
        _statusMessage = 'AUDIT COMPLETE (${res.elapsedMs} ms): ${res.verdictLabel}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditing = false;
        _statusMessage = 'ERR: Forensic Audit Fault: $e';
      });
    }
  }

  Future<void> _generateSpectrogram() async {
    final report = _report;
    if (report == null || _renderingSpec || _loading) return;
    TapFeedback.machineTap();
    final oldSpec = _spectrogramPath;
    setState(() {
      _renderingSpec = true;
      _spectrogramPath = null;
      _statusMessage = 'RENDERING 1600x800 LOGARITHMIC SPECTROGRAM...';
    });
    _deleteTempSpectrogram(oldSpec);
    try {
      final specPath = await MediaForensics.renderSpectrogram(report.filePath);
      if (!mounted) {
        _deleteTempSpectrogram(specPath);
        return;
      }
      if (specPath != null) {
        TapFeedback.machineConfirm();
        setState(() {
          _spectrogramPath = specPath;
          _renderingSpec = false;
          _statusMessage = 'SPECTROGRAM READY — PINCH TO ZOOM HIGH-FREQUENCY SHELF.';
        });
      } else {
        setState(() {
          _renderingSpec = false;
          _statusMessage = 'ERR: Spectrogram Render Returned Empty Output.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _renderingSpec = false;
        _statusMessage = 'ERR: Spectrogram Fault: $e';
      });
    }
  }

  Future<void> _copyReport({required bool asJson}) async {
    final report = _report;
    if (report == null) return;
    TapFeedback.machineTap();
    final content = asJson ? report.toRawJsonText(audit: _audit) : report.toMediaInfoText(audit: _audit);
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    setState(() => _statusMessage = 'COPIED ${asJson ? 'RAW FFPROBE JSON' : 'MEDIAINFO REPORT'} TO CLIPBOARD.');
  }

  Future<void> _exportReport({required bool asJson}) async {
    final report = _report;
    if (report == null) return;
    TapFeedback.machineTap();
    final dot = report.fileName.lastIndexOf('.');
    final base = dot > 0 ? report.fileName.substring(0, dot) : report.fileName;
    final fileName = asJson ? '${base}_ffprobe.json' : '${base}_mediainfo.txt';
    final mime = asJson ? 'application/json' : 'text/plain';
    final content = asJson ? report.toRawJsonText(audit: _audit) : report.toMediaInfoText(audit: _audit);
    final savedLoc = await StorageClient.exportTextToDownloads(
      fileName: fileName,
      content: content,
      mimeType: mime,
    );
    if (!mounted) return;
    if (savedLoc != null) {
      TapFeedback.machineConfirm();
      setState(() => _statusMessage = 'EXPORTED REPORT -> $savedLoc');
    } else {
      setState(() => _statusMessage = 'ERR: Could Not Write Report To Downloads.');
    }
  }

  void _sendToForge() {
    final report = _report;
    if (report == null) return;
    TapFeedback.machineTap();
    Navigator.of(context).popUntil((route) => route.isFirst);
    SovereignState.sendToForge(
      ForgeRequest(
        path: report.filePath,
        origin: ForgeOrigin.picked,
      ),
    );
  }

  Future<void> _executeLosslessExtract() async {
    final report = _report;
    if (report == null || _runningSurgery) return;
    TapFeedback.machineTap();
    setState(() {
      _runningSurgery = true;
      _statusMessage = 'DEMUXING AUDIO STREAM (-c:a copy, ZERO RE-ENCODE)...';
    });
    final res = await MediaForensics.extractAudioLossless(report);
    if (!mounted) return;
    if (res.ok) TapFeedback.machineConfirm();
    setState(() {
      _runningSurgery = false;
      _statusMessage = res.summary;
    });
  }

  Future<void> _executeFastStart() async {
    final report = _report;
    if (report == null || _runningSurgery) return;
    TapFeedback.machineTap();
    setState(() {
      _runningSurgery = true;
      _statusMessage = 'RELOCATING MOOV ATOM (-movflags +faststart, -c copy)...';
    });
    final res = await MediaForensics.remuxFastStart(report);
    if (!mounted) return;
    if (res.ok) TapFeedback.machineConfirm();
    setState(() {
      _runningSurgery = false;
      _statusMessage = res.summary;
    });
  }

  Future<void> _executeChapterSplit() async {
    final report = _report;
    if (report == null || _runningSurgery || report.chapters.isEmpty) return;
    TapFeedback.machineTap();
    setState(() {
      _runningSurgery = true;
      _statusMessage = 'SPLITTING ${report.chapters.length} CHAPTERS LOSSLESSLY (-c copy)...';
    });
    final res = await MediaForensics.splitChaptersLossless(
      report,
      onProgress: (cur, total, title) {
        if (!mounted) return;
        setState(() => _statusMessage = 'SPLITTING CHAPTER $cur/$total: $title');
      },
    );
    if (!mounted) return;
    if (res.ok) TapFeedback.machineConfirm();
    setState(() {
      _runningSurgery = false;
      _statusMessage = res.summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, accentColor, _) {
        final report = _report;
        final isErr = _statusMessage.startsWith('ERR:');
        final busy = _loading || _auditing || _renderingSpec || _runningSurgery;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: accentColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'MEDIAINFO & FORENSICS',
              style: TextStyle(
                fontFamily: 'ShareTechMono',
                color: accentColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'MOUNT ANY FILE',
                icon: Icon(Icons.folder_open, color: accentColor),
                onPressed: busy ? null : _pickAndInspect,
              ),
              if (report != null && TagIO.canWrite(report.filePath))
                IconButton(
                  tooltip: 'OPEN IN FORGE',
                  icon: const Icon(Icons.edit_note, color: Colors.purpleAccent),
                  onPressed: busy ? null : _sendToForge,
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: accentColor.withValues(alpha: 0.35), height: 1.0),
            ),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CyberBackdrop(
                  accentColor: accentColor,
                  variant: BackdropVariant.workbench,
                  intensity: 0.85,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (busy)
                    LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.84),
                      border: Border.all(color: isErr ? Colors.redAccent : accentColor.withValues(alpha: 0.8)),
                    ),
                    child: Text(
                      '> $_statusMessage',
                      style: TextStyle(
                        fontFamily: 'VT323',
                        fontSize: 15,
                        color: isErr ? Colors.redAccent : accentColor,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (report != null) _buildModeBar(accentColor),
                  Expanded(
                    child: report == null
                        ? _buildEmptyState(accentColor, busy)
                        : switch (_tab) {
                            _InspectorTab.tree => _buildTreeView(report, accentColor),
                            _InspectorTab.text => _buildRawReportView(report, accentColor, asJson: false),
                            _InspectorTab.json => _buildRawReportView(report, accentColor, asJson: true),
                            _InspectorTab.forensics => _buildForensicsView(report, accentColor),
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeBar(Color accentColor) {
    Widget tabBtn(_InspectorTab mode, String label, IconData icon) {
      final active = _tab == mode;
      return Expanded(
        child: InkWell(
          onTap: () {
            TapFeedback.machineTap();
            setState(() => _tab = mode);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? accentColor.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.78),
              border: Border.all(color: active ? accentColor : Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: active ? accentColor : Colors.white54),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'ShareTechMono',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: active ? accentColor : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          tabBtn(_InspectorTab.tree, 'TREE', Icons.account_tree_outlined),
          const SizedBox(width: 6),
          tabBtn(_InspectorTab.text, 'TEXT', Icons.subject),
          const SizedBox(width: 6),
          tabBtn(_InspectorTab.json, 'JSON', Icons.data_object),
          const SizedBox(width: 6),
          tabBtn(_InspectorTab.forensics, 'FORENSICS', Icons.graphic_eq),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color accentColor, bool busy) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            border: Border.all(color: accentColor.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined, size: 54, color: accentColor.withValues(alpha: 0.8)),
              const SizedBox(height: 14),
              Text(
                'SOVEREIGN DEEP INSPECTOR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inspect container atoms, audio/video/subtitle streams, bit depth, sample rate, color space, FastStart streamability, chapters, fake-lossless shelves, EBU R128 loudness, and lossless -c copy remux tools.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),
              CyberTapFeedback(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _pickAndInspect,
                  icon: Icon(Icons.folder_open, color: accentColor),
                  label: Text(
                    'MOUNT AUDIO / VIDEO FILE',
                    style: TextStyle(fontFamily: 'ShareTechMono', color: accentColor, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: accentColor),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreeView(MediaInspectionReport report, Color accentColor) {
    final mergedTags = <String, String>{...report.containerTags};
    for (final e in report.id3Tags.entries) {
      if (e.key == 'ARTWORK_BASE64' || e.key == 'DURATION_MS' || e.value.trim().isEmpty) continue;
      mergedTags.putIfAbsent(e.key, () => e.value);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _buildHeroCard(report, accentColor),
        const SizedBox(height: 12),
        _buildActionStrip(accentColor),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'GENERAL // CONTAINER',
          color: accentColor,
          rows: [
            ('FILE NAME', report.fileName),
            ('PATH', report.filePath),
            ('CONTAINER', report.containerFormat.toUpperCase()),
            ('FORMAT INFO', report.containerLongFormat),
            ('FILE SIZE', '${MediaForensics.formatBytes(report.fileSizeBytes)} (${report.fileSizeBytes} B)'),
            ('DURATION', MediaForensics.formatDurationPrecise(report.durationSeconds)),
            ('BITRATE MODE', report.bitrateMode),
            if (report.overallBitrateBps != null)
              ('OVERALL BITRATE', MediaForensics.formatBitrate(report.overallBitrateBps!)),
            if (report.isFastStart != null)
              ('FASTSTART (MOOV)', report.isFastStart! ? 'YES (STREAMABLE)' : 'NO (MDAT BEFORE MOOV)'),
            ('WRITING APP', report.writingApp),
            ('STREAMS', '${report.audioStreams.length} AUDIO • ${report.videoStreams.length} VIDEO • ${report.subtitleStreams.length} SUB'),
            if (report.chapters.isNotEmpty) ('CHAPTERS', '${report.chapters.length} EMBEDDED'),
            if (report.coverInfo != null)
              (
                'EMBEDDED ART',
                '${report.coverInfo!.format}'
                    '${report.coverInfo!.width != null ? ' • ${report.coverInfo!.width}x${report.coverInfo!.height}' : ''}'
                    ' • ${MediaForensics.formatBytes(report.coverInfo!.byteLength)}'
              ),
          ],
        ),
        for (var i = 0; i < report.audioStreams.length; i++) ...[
          const SizedBox(height: 12),
          _buildAudioStreamCard(report.audioStreams[i], i + 1),
        ],
        for (var i = 0; i < report.videoStreams.length; i++) ...[
          const SizedBox(height: 12),
          _buildVideoStreamCard(report.videoStreams[i], i + 1),
        ],
        for (var i = 0; i < report.subtitleStreams.length; i++) ...[
          const SizedBox(height: 12),
          _sectionCard(
            title: 'TEXT / SUBTITLE #${i + 1} (STREAM ${report.subtitleStreams[i].index})',
            color: Colors.amberAccent,
            rows: [
              ('CODEC', report.subtitleStreams[i].codec.toUpperCase()),
              ('CODEC INFO', report.subtitleStreams[i].codecLong),
              ('LANGUAGE', report.subtitleStreams[i].language),
              ('TITLE', report.subtitleStreams[i].title),
            ],
          ),
        ],
        if (report.chapters.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildChaptersCard(report, accentColor),
        ],
        if (mergedTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionCard(
            title: 'METADATA TAGS (${mergedTags.length})',
            color: Colors.purpleAccent,
            rows: [
              for (final e in mergedTags.entries)
                (
                  e.key.toUpperCase(),
                  e.key.toLowerCase() == 'lyrics'
                      ? '[EMBEDDED LYRICS • ${e.value.split('\n').length} LINES • ${e.value.length} CHARS]'
                      : e.value,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHeroCard(MediaInspectionReport report, Color accentColor) {
    final audio = report.primaryAudio;
    final video = report.primaryVideo;
    final badges = <(String, Color)>[
      (report.extension.isEmpty ? report.containerFormat.toUpperCase() : report.extension.toUpperCase(), accentColor),
      if (audio != null)
        (
          MediaForensics.isLosslessCodec(audio.codec) ? 'LOSSLESS CODEC' : 'LOSSY CODEC',
          MediaForensics.isLosslessCodec(audio.codec) ? Colors.greenAccent : Colors.amberAccent,
        ),
      if (audio?.sampleRateHz != null) ('${(audio!.sampleRateHz! / 1000.0).toStringAsFixed(1)} KHZ', Colors.cyanAccent),
      if (audio?.bitsPerSample != null) ('${audio!.bitsPerSample}-BIT', Colors.purpleAccent),
      if (video?.width != null && video?.height != null) ('${video!.width}x${video.height}', Colors.cyanAccent),
      if (report.isFastStart == true) ('FASTSTART', Colors.greenAccent),
      if (report.chapters.isNotEmpty) ('${report.chapters.length} CH', Colors.amberAccent),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        border: Border.all(color: accentColor.withValues(alpha: 0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.coverInfo != null) ...[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(border: Border.all(color: accentColor.withValues(alpha: 0.5))),
              child: Image.memory(report.coverInfo!.bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titleHint?.trim().isNotEmpty == true ? widget.titleHint! : report.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'ShareTechMono',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${MediaForensics.formatBytes(report.fileSizeBytes)} • ${MediaForensics.formatDurationPrecise(report.durationSeconds)}'
                  '${report.overallBitrateBps != null ? ' • ${MediaForensics.formatBitrate(report.overallBitrateBps!)}' : ''}',
                  style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (label, c) in badges)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          border: Border.all(color: c.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, fontWeight: FontWeight.bold, color: c),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(Color accentColor) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _copyReport(asJson: false),
            icon: Icon(Icons.copy, size: 15, color: accentColor),
            label: Text('COPY TXT', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: accentColor)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: accentColor.withValues(alpha: 0.7)),
              backgroundColor: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _exportReport(asJson: false),
            icon: const Icon(Icons.download, size: 15, color: Colors.cyanAccent),
            label: const Text('SAVE .TXT', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.cyanAccent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.7)),
              backgroundColor: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _tab = _InspectorTab.forensics);
              if (_audit == null) _runForensics();
            },
            icon: const Icon(Icons.verified_outlined, size: 15, color: Colors.greenAccent),
            label: const Text('AUDIT', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.greenAccent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.7)),
              backgroundColor: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioStreamCard(StreamEntry a, int ordinal) {
    return _sectionCard(
      title: 'AUDIO STREAM #$ordinal (INDEX ${a.index})',
      color: Colors.greenAccent,
      rows: [
        ('CODEC', a.codec.toUpperCase()),
        ('CODEC INFO', a.codecLong),
        ('PROFILE', a.profile),
        ('CODEC TAG', a.codecTag),
        ('COMPRESSION', MediaForensics.isLosslessCodec(a.codec) ? 'LOSSLESS' : 'LOSSY'),
        if (a.sampleRateHz != null) ('SAMPLE RATE', '${a.sampleRateHz} Hz (${(a.sampleRateHz! / 1000.0).toStringAsFixed(2)} kHz)'),
        if (a.bitsPerSample != null) ('BIT DEPTH', '${a.bitsPerSample}-bit'),
        ('SAMPLE FORMAT', a.sampleFormat),
        if (a.channels != null) ('CHANNELS', '${a.channels}'),
        ('CHANNEL LAYOUT', a.channelLayout),
        if (a.bitrateBps != null) ('STREAM BITRATE', MediaForensics.formatBitrate(a.bitrateBps!)),
        ('DEFAULT TRACK', a.isDefault ? 'YES' : 'NO'),
        ('LANGUAGE', a.language),
        ('TITLE', a.title),
      ],
    );
  }

  Widget _buildVideoStreamCard(StreamEntry v, int ordinal) {
    return _sectionCard(
      title: 'VIDEO STREAM #$ordinal (INDEX ${v.index})',
      color: Colors.cyanAccent,
      rows: [
        ('CODEC', v.codec.toUpperCase()),
        ('CODEC INFO', v.codecLong),
        ('PROFILE', v.profile),
        ('CODEC TAG', v.codecTag),
        if (v.width != null && v.height != null) ('RESOLUTION', '${v.width} x ${v.height}'),
        ('DISPLAY ASPECT', v.dar),
        ('SAMPLE ASPECT', v.sar),
        ('FRAME RATE MODE', v.isVariableFrameRate ? 'VARIABLE (VFR)' : 'CONSTANT (CFR)'),
        if (v.avgFrameRate.isNotEmpty) ('FRAME RATE', '${v.avgFrameRate} FPS'),
        if (v.isVariableFrameRate && v.realFrameRate.isNotEmpty) ('BASE FRAME RATE', '${v.realFrameRate} FPS'),
        ('PIXEL FORMAT', v.pixelFormat),
        if (v.bitsPerSample != null) ('BIT DEPTH', '${v.bitsPerSample}-bit'),
        ('COLOR SPACE', v.colorSpace),
        ('COLOR TRANSFER', v.colorTransfer),
        ('COLOR PRIMARIES', v.colorPrimaries),
        if (v.bitrateBps != null) ('STREAM BITRATE', MediaForensics.formatBitrate(v.bitrateBps!)),
        if (v.nbFrames != null) ('FRAME COUNT', '${v.nbFrames}'),
        ('LANGUAGE', v.language),
      ],
    );
  }

  Widget _buildChaptersCard(MediaInspectionReport report, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MENU // EMBEDDED CHAPTERS (${report.chapters.length})',
                  style: const TextStyle(
                    fontFamily: 'ShareTechMono',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _runningSurgery ? null : _executeChapterSplit,
                icon: const Icon(Icons.call_split, size: 14, color: Colors.amberAccent),
                label: const Text('SPLIT ALL (-c copy)', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.amberAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amberAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
          for (var i = 0; i < report.chapters.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      MediaForensics.formatTimestampMs((report.chapters[i].startSeconds * 1000).round()),
                      style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: accentColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${(i + 1).toString().padLeft(2, '0')}. ${report.chapters[i].title}',
                      style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Color color,
    required List<(String, String)> rows,
  }) {
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        border: Border.all(color: color.withValues(alpha: 0.50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'ShareTechMono',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
          for (final (k, v) in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 126,
                    child: Text(
                      k,
                      style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      v,
                      style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRawReportView(MediaInspectionReport report, Color accentColor, {required bool asJson}) {
    final text = asJson ? report.toRawJsonText(audit: _audit) : report.toMediaInfoText(audit: _audit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyReport(asJson: asJson),
                  icon: Icon(Icons.copy, size: 15, color: accentColor),
                  label: Text(
                    asJson ? 'COPY JSON' : 'COPY MEDIAINFO TEXT',
                    style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: accentColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: accentColor),
                    backgroundColor: Colors.black.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportReport(asJson: asJson),
                  icon: const Icon(Icons.download, size: 15, color: Colors.cyanAccent),
                  label: Text(
                    asJson ? 'EXPORT .JSON' : 'EXPORT .TXT',
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.cyanAccent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.cyanAccent),
                    backgroundColor: Colors.black.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 11,
                  color: Colors.white,
                  height: 1.38,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForensicsView(MediaInspectionReport report, Color accentColor) {
    final audit = _audit;
    Color verdictColor = accentColor;
    if (audit != null) {
      verdictColor = switch (audit.verdict) {
        ForensicVerdict.trueLossless => Colors.greenAccent,
        ForensicVerdict.lossyNative => Colors.cyanAccent,
        ForensicVerdict.zeroPaddedBitDepth => Colors.amberAccent,
        ForensicVerdict.suspectLossyShelf => Colors.orangeAccent,
        ForensicVerdict.fakeLosslessBrickwall => Colors.redAccent,
        ForensicVerdict.corruptStream => Colors.redAccent,
        ForensicVerdict.unknown => Colors.white54,
      };
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            border: Border.all(color: verdictColor.withValues(alpha: 0.75)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'AUTHENTICITY, LOUDNESS & BITSTREAM AUDIT',
                style: TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Decodes the full audio stream via FFmpeg astats + EBU R128 and probes 16.2 kHz / 19.5 kHz spectral shelves to expose upsampled MP3s disguised as FLAC/WAV, zero-padded 24-bit files, clipping, and corrupt frames.',
                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 12),
              CyberTapFeedback(
                child: OutlinedButton.icon(
                  onPressed: _auditing || report.primaryAudio == null ? null : _runForensics,
                  icon: _auditing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                        )
                      : const Icon(Icons.radar, color: Colors.greenAccent, size: 18),
                  label: Text(
                    audit == null ? 'RUN DEEP FORENSIC AUDIT' : 'RE-RUN DEEP FORENSIC AUDIT',
                    style: const TextStyle(
                      fontFamily: 'ShareTechMono',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.greenAccent),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              if (audit != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: verdictColor.withValues(alpha: 0.12),
                    border: Border.all(color: verdictColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audit.verdictLabel,
                        style: TextStyle(
                          fontFamily: 'ShareTechMono',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: verdictColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        audit.verdictDetail,
                        style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _metricRow('INTEGRATED LOUDNESS', audit.integratedLufs != null ? '${audit.integratedLufs!.toStringAsFixed(2)} LUFS' : 'N/A'),
                _metricRow('LOUDNESS RANGE (LRA)', audit.loudnessRangeLu != null ? '${audit.loudnessRangeLu!.toStringAsFixed(2)} LU' : 'N/A'),
                _metricRow('TRUE PEAK', audit.truePeakDbtp != null ? '${audit.truePeakDbtp!.toStringAsFixed(2)} dBTP' : 'N/A'),
                _metricRow(
                  'CREST DYNAMIC RANGE',
                  audit.dynamicRangeDb != null ? 'DR${audit.dynamicRangeDb!.round()} (${audit.dynamicRangeDb!.toStringAsFixed(2)} dB)' : 'N/A',
                ),
                _metricRow(
                  'SAMPLE PEAK / RMS',
                  '${audit.peakLevelDb?.toStringAsFixed(2) ?? 'N/A'} / ${audit.rmsLevelDb?.toStringAsFixed(2) ?? 'N/A'} dBFS',
                ),
                _metricRow('EFFECTIVE BIT DEPTH', audit.effectiveBitDepth),
                if (audit.band16kRmsDb != null)
                  _metricRow('HF ENERGY >= 16.2 KHZ', '${audit.band16kRmsDb!.toStringAsFixed(1)} dBFS'),
                if (audit.band19k5RmsDb != null)
                  _metricRow('HF ENERGY >= 19.5 KHZ', '${audit.band19k5RmsDb!.toStringAsFixed(1)} dBFS'),
                if (audit.dcOffset != null) _metricRow('DC OFFSET', audit.dcOffset!.toStringAsFixed(6)),
                _metricRow('NAN / INF SAMPLES', '${audit.nanInfCount}'),
                _metricRow(
                  'BITSTREAM HEALTH',
                  audit.decodeErrors.isEmpty ? 'CLEAN (0 DECODE ERRORS)' : '${audit.decodeErrors.length} ERROR(S)',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'HIGH-RESOLUTION SPECTROGRAM (PINCH ZOOM)',
                style: TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Renders a 1600x800 logarithmic frequency heatmap via FFmpeg showspectrumpic to visually inspect transcode brickwalls.',
                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _renderingSpec || report.primaryAudio == null ? null : _generateSpectrogram,
                icon: _renderingSpec
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                      )
                    : const Icon(Icons.insights, color: Colors.cyanAccent, size: 18),
                label: Text(
                  _spectrogramPath == null ? 'RENDER HD SPECTROGRAM' : 'REFRESH HD SPECTROGRAM',
                  style: const TextStyle(
                    fontFamily: 'ShareTechMono',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.cyanAccent),
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              if (_spectrogramPath != null && File(_spectrogramPath!).existsSync()) ...[
                const SizedBox(height: 12),
                Container(
                  height: 230,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.45)),
                  ),
                  child: ClipRect(
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Image.file(
                        File(_spectrogramPath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.65)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'LOSSLESS CONTAINER SURGERY (-c copy, ZERO RE-ENCODE)',
                style: TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.purpleAccent,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pure stream-copy operations that preserve 100% original audio bits without generation loss and export directly to Music.',
                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (report.primaryAudio != null)
                OutlinedButton.icon(
                  onPressed: _runningSurgery ? null : _executeLosslessExtract,
                  icon: const Icon(Icons.audiotrack, color: Colors.purpleAccent, size: 17),
                  label: Text(
                    'EXTRACT AUDIO STREAM (-c:a copy -> .${MediaForensics.losslessAudioExtensionForCodec(report.primaryAudio!.codec) ?? 'audio'})',
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.purpleAccent),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              if (report.supportsFastStart) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _runningSurgery ? null : _executeFastStart,
                  icon: const Icon(Icons.bolt, color: Colors.amberAccent, size: 17),
                  label: Text(
                    report.isFastStart == true
                        ? 'RE-WRITE MP4/M4A FASTSTART (ALREADY STREAMABLE)'
                        : 'OPTIMIZE MP4/M4A FASTSTART (+faststart)',
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.amberAccent),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
              if (report.chapters.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _runningSurgery ? null : _executeChapterSplit,
                  icon: const Icon(Icons.call_split, color: Colors.greenAccent, size: 17),
                  label: Text(
                    'SPLIT ${report.chapters.length} CHAPTERS TO TRACKS (-c copy)',
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.greenAccent),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
