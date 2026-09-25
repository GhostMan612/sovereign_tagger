// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import '../core/playback_fx.dart';

class EqPresetsScreen extends StatefulWidget {
  const EqPresetsScreen({super.key});

  @override
  State<EqPresetsScreen> createState() => _EqPresetsScreenState();
}

class _EqPresetsScreenState extends State<EqPresetsScreen> {
  final List<double> _eqBands15 = List.filled(15, 0.0);
  static const List<int> _freqs = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];
  static const double _bandWidth = 52.0;
  static const double _railHeight = 260.0;

  bool _dirty = false;
  List<double> _saved = List.filled(15, 0.0);

  static const Map<String, List<double>> _presets = {
    'FLAT': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'BASS BOOST': [7, 6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'BASS CUT': [-6, -5, -4, -3, -2, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'TREBLE BOOST': [0, 0, 0, 0, 0, 0, 0, 0, 0.5, 1.5, 3, 4, 5, 6, 6],
    'VOCAL': [-2, -2, -1.5, -1, 0, 1.5, 3, 3.5, 3, 2, 1, 0, 0, -1, -1],
    'ROCK': [5, 4, 3, 1.5, -0.5, -1.5, -1, 0.5, 1.5, 2.5, 3.5, 4, 4, 4, 4],
    'POP': [-1, -0.5, 0.5, 1.5, 3, 3.5, 3, 1.5, 0, -0.5, -0.5, 0, 0.5, 1, 1],
    'HIP-HOP': [6, 5.5, 4.5, 3, 1.5, 0, -0.5, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 2.5],
    'ELECTRONIC': [5, 4.5, 3.5, 2, 0.5, -1, -1.5, -0.5, 1, 2, 3, 3.5, 4, 4.5, 4.5],
    'JAZZ': [3, 2.5, 2, 1.5, 1, 0, -0.5, -0.5, 0, 1, 1.5, 2, 2.5, 3, 3],
    'CLASSICAL': [3, 3, 2.5, 2, 1, 0, 0, 0, 0, 0, 0.5, 1.5, 2.5, 3, 3.5],
    'LOUDNESS': [6, 5, 3.5, 1.5, 0, -1, -1.5, -1, 0, 0.5, 1.5, 3, 4.5, 5.5, 6],
    'SMALL SPEAKER': [-6, -4, -2, 1, 3, 3.5, 3, 2, 1, 1, 1.5, 2, 2, 1.5, 1],
  };

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    if (!mounted) return;
    setState(() {
      final gains = PlaybackFx.eqGains.value;
      for (int i = 0; i < 15; i++) {
        _eqBands15[i] = i < gains.length ? gains[i] : 0.0;
      }
      _saved = List<double>.from(_eqBands15);
      _dirty = false;
    });
  }

  void _live() {
    PlaybackFx.setEqGains(_eqBands15);
  }

  void _applyPreset(List<double> values) {
    setState(() {
      for (int i = 0; i < 15; i++) {
        _eqBands15[i] = values[i];
      }
      _dirty = true;
    });
    if (!PlaybackFx.eqEnabled.value) PlaybackFx.setEqEnabled(true);
    _live();
  }

  Future<void> _savePreset() async {
    await PlaybackFx.setEqGains(_eqBands15, persist: true);
    _saved = List<double>.from(_eqBands15);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('> 15-BAND EQ PRESET SAVED TO KERNEL.', style: TextStyle(fontFamily: 'ShareTechMono')),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.purpleAccent)),
    ));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.purpleAccent)),
        title: const Text("UNSAVED PRESET", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, color: Colors.purpleAccent)),
        content: const Text("DISCARD UNSAVED EQ CHANGES?", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("STAY", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DISCARD", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent))),
        ],
      ),
    );
    if (discard == true && mounted) {
      await PlaybackFx.setEqGains(_saved);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _dirty) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.purpleAccent), onPressed: () => Navigator.maybePop(context)),
          title: const Text("15-BAND EQUALIZER", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(color: Colors.purpleAccent.withValues(alpha: 0.3), height: 1.0),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.tune, color: Colors.purpleAccent, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text("AUTOEQ RACK — ±12dB, Q=1.2", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.purpleAccent))),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: PlaybackFx.eqEnabled,
                      builder: (context, enabled, _) => SwitchListTile(
                        dense: true,
                        title: Text(enabled ? "EQ ACTIVE ON PLAYBACK" : "EQ BYPASSED", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: enabled ? Colors.purpleAccent : Colors.white54)),
                        subtitle: ValueListenableBuilder<List<double>>(
                          valueListenable: PlaybackFx.deviceBands,
                          builder: (context, bands, _) => Text(
                            bands.isEmpty
                                ? "Device EQ attaches when playback starts."
                                : "Curve mapped onto this phone's ${bands.length}-band EQ (${bands.map((f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(1)}k' : f.round().toString()).join(' / ')} Hz).",
                            style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38),
                          ),
                        ),
                        activeThumbColor: Colors.purpleAccent,
                        value: enabled,
                        onChanged: (v) => PlaybackFx.setEqEnabled(v),
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final e in _presets.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(e.key, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                                backgroundColor: Colors.black,
                                side: const BorderSide(color: Colors.purpleAccent),
                                onPressed: () => _applyPreset(e.value),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: List.generate(15, (i) => _buildBand(i)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _dirty ? _savePreset : null,
                    icon: const Icon(Icons.save, color: Colors.purpleAccent, size: 18),
                    label: const Text("SAVE PRESET", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.purpleAccent), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _applyPreset(_presets['FLAT']!),
                    icon: const Icon(Icons.restart_alt, color: Colors.redAccent, size: 18),
                    label: const Text("FLAT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "CHANGES ARE HEARD LIVE. SAVE PRESET KEEPS THEM ACROSS RESTARTS AND FEEDS THE WORKBENCH 15-BAND EQUALIZER OPERATION.",
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBand(int i) {
    final label = _freqs[i] >= 1000 ? "${(_freqs[i] / 1000).toStringAsFixed(1)}k" : "${_freqs[i]}";
    return SizedBox(
      width: _bandWidth,
      child: Column(
        children: [
          Text("$label Hz", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, fontWeight: FontWeight.bold, color: _eqBands15[i] == 0.0 ? Colors.white38 : Colors.purpleAccent)),
          const SizedBox(height: 6),
          SizedBox(
            width: _bandWidth,
            height: _railHeight,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  activeTrackColor: Colors.purpleAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.purpleAccent,
                  overlayColor: Colors.purpleAccent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _eqBands15[i], min: -12, max: 12, divisions: 24,
                  onChanged: (val) => setState(() { _eqBands15[i] = val; _dirty = true; }),
                  onChangeEnd: (_) => _live(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: _eqBands15[i] == 0.0 ? Colors.white24 : Colors.purpleAccent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text("${_eqBands15[i] >= 0 ? '+' : ''}${_eqBands15[i].toStringAsFixed(1)}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
