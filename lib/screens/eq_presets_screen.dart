// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < 15; i++) {
        _eqBands15[i] = prefs.getDouble('eq15_band_$i') ?? 0.0;
      }
      _dirty = false;
    });
  }

  Future<void> _savePreset() async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < 15; i++) {
      await prefs.setDouble('eq15_band_$i', _eqBands15[i]);
    }
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
    if (discard == true && mounted) Navigator.pop(context);
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
                    onPressed: () => setState(() {
                      for (int i = 0; i < 15; i++) {
                        _eqBands15[i] = 0.0;
                      }
                      _dirty = true;
                    }),
                    icon: const Icon(Icons.restart_alt, color: Colors.redAccent, size: 18),
                    label: const Text("FLAT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "PRESETS PERSIST TO KERNEL PREFS AND FEED THE WORKBENCH 15-BAND EQUALIZER OPERATION.",
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
