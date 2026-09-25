// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ffmpeg_executor.dart';

class PlaybackEngineScreen extends StatefulWidget {
  const PlaybackEngineScreen({super.key});

  @override
  State<PlaybackEngineScreen> createState() => _PlaybackEngineScreenState();
}

class _PlaybackEngineScreenState extends State<PlaybackEngineScreen> {
  double _crossfadeDuration = 0.0;
  bool _gaplessEnabled = true;

  bool _isGaplessAuditing = false;
  String _gaplessAuditResult = "";

  @override
  void initState() {
    super.initState();
    _loadEngine();
  }

  Future<void> _loadEngine() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _crossfadeDuration = prefs.getDouble('crossfade_duration') ?? 0.0;
      _gaplessEnabled = prefs.getBool('gapless_enabled') ?? true;
    });
  }

  Future<void> _persistCrossfade(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('crossfade_duration', val);
  }

  Future<void> _persistGapless(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gapless_enabled', val);
  }

  Future<void> _runGaplessAudit() async {
    setState(() { _isGaplessAuditing = true; _gaplessAuditResult = "Generating test tones..."; });
    try {
      final tempDir = await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('getTempDirectory');
      final tone1Path = "$tempDir/gapless_tone1_440hz.wav";
      final tone2Path = "$tempDir/gapless_tone2_880hz.wav";
      final concatPath = "$tempDir/gapless_audit_${DateTime.now().millisecondsSinceEpoch}.wav";

      await FFmpegExecutor.execute('-y -f lavfi -i "sine=frequency=440:duration=1:sample_rate=44100" -c:a pcm_s16le "$tone1Path"');
      await FFmpegExecutor.execute('-y -f lavfi -i "sine=frequency=880:duration=1:sample_rate=44100" -c:a pcm_s16le "$tone2Path"');
      await FFmpegExecutor.execute('-y -i "$tone1Path" -i "$tone2Path" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" -c:a pcm_s16le "$concatPath"');

      final session = await FFmpegExecutor.execute('-y -i "$concatPath" -af "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level" -f null -');
      final output = session.getOutput() ?? "";

      final rmsMatches = RegExp(r'RMS_level=(-?\d+\.?\d*)').allMatches(output).toList();

      if (!mounted) return;
      if (rmsMatches.length >= 2) {
        final rmsValues = rmsMatches.map((m) => double.tryParse(m.group(1) ?? "") ?? 0.0).toList();
        final minRms = rmsValues.reduce((a, b) => a < b ? a : b);
        final maxRms = rmsValues.reduce((a, b) => a > b ? a : b);

        final gapless = minRms > (maxRms * 0.1);

        setState(() => _gaplessAuditResult = gapless
            ? "GAPLESS: PASS ✓\nConcatenatingAudioSource shows continuous playback (min RMS: ${minRms.toStringAsFixed(2)} dB, max: ${maxRms.toStringAsFixed(2)} dB)"
            : "GAPLESS: POTENTIAL GAP DETECTED ⚠\nMin RMS: ${minRms.toStringAsFixed(2)} dB, Max: ${maxRms.toStringAsFixed(2)} dB\n(Threshold: ${(maxRms * 0.1).toStringAsFixed(2)} dB)");
      } else {
        setState(() => _gaplessAuditResult = "AUDIT INCONCLUSIVE: Could not parse RMS levels from FFmpeg output.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _gaplessAuditResult = "ERR: Gapless Audit Fault: $e");
    } finally {
      if (mounted) setState(() => _isGaplessAuditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent), onPressed: () => Navigator.pop(context)),
        title: const Text("PLAYBACK ENGINE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.cyanAccent.withValues(alpha: 0.3), height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.merge_type, color: Colors.cyanAccent, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text("TRANSITION MACHINE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("CROSSFADE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                          Text("${_crossfadeDuration.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent)),
                        ],
                      ),
                      Slider(
                        value: _crossfadeDuration, min: 0, max: 12, divisions: 24,
                        activeColor: Colors.cyanAccent, inactiveColor: Colors.white24,
                        onChanged: (val) => setState(() => _crossfadeDuration = val),
                        onChangeEnd: _persistCrossfade,
                      ),
                      const Divider(color: Colors.white12, height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("GAPLESS PLAYBACK", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                        subtitle: const Text("ConcatenatingAudioSource default — zero silence between tracks", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                        activeThumbColor: Colors.cyanAccent,
                        activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.3),
                        value: _gaplessEnabled,
                        onChanged: (val) {
                          setState(() => _gaplessEnabled = val);
                          _persistGapless(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isGaplessAuditing ? null : _runGaplessAudit,
                    icon: _isGaplessAuditing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                        : const Icon(Icons.science, color: Colors.cyanAccent, size: 18),
                    label: const Text("RUN GAPLESS AUDIT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent), padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                  if (_gaplessAuditResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text("> $_gaplessAuditResult", style: const TextStyle(fontFamily: 'VT323', fontSize: 13, color: Colors.white70, height: 1.3)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "CHANGES WRITE DIRECTLY TO KERNEL PREFS. GAPLESS AUDIT SYNTHESIZES A 2-TONE PATTERN AND MEASURES THE INTER-TRACK FLOOR.",
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
