// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import '../core/playback_fx.dart';

class PlaybackEngineScreen extends StatelessWidget {
  const PlaybackEngineScreen({super.key});

  static const TextStyle _label = TextStyle(fontFamily: 'ShareTechMono', color: Colors.white);
  static const TextStyle _hint = TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11, height: 1.35);

  Widget _panel({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panel(
              icon: Icons.merge_type,
              title: "TRANSITIONS",
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: PlaybackFx.fadeSeconds,
                  builder: (context, seconds, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("FADE OUT / FADE IN", style: _label),
                          Text(seconds <= 0 ? "OFF" : "${seconds.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent)),
                        ],
                      ),
                      Slider(
                        value: seconds,
                        min: 0,
                        max: 12,
                        divisions: 24,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => PlaybackFx.fadeSeconds.value = v,
                        onChangeEnd: PlaybackFx.setFadeSeconds,
                      ),
                    ],
                  ),
                ),
                const Text(
                  "Fades each track out at its end and the next one in. Tracks never overlap. Leave OFF for gapless albums (live sets, DJ mixes): playback is always gapless.",
                  style: _hint,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _panel(
              icon: Icons.volume_up,
              title: "REPLAYGAIN",
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: PlaybackFx.replayGainMode,
                  builder: (context, mode, _) => Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const ['off', 'track', 'album'])
                        ChoiceChip(
                          label: Text(m.toUpperCase(), style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: mode == m ? Colors.black : Colors.white70)),
                          selected: mode == m,
                          selectedColor: Colors.cyanAccent,
                          backgroundColor: Colors.black,
                          side: BorderSide(color: mode == m ? Colors.cyanAccent : Colors.white24),
                          showCheckmark: false,
                          onSelected: (_) => PlaybackFx.setReplayGainMode(m),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<double>(
                  valueListenable: PlaybackFx.replayGainPreamp,
                  builder: (context, db, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("PRE-AMP", style: _label),
                          Text("${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent)),
                        ],
                      ),
                      Slider(
                        value: db,
                        min: -6,
                        max: 6,
                        divisions: 24,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => PlaybackFx.replayGainPreamp.value = v,
                        onChangeEnd: PlaybackFx.setReplayGainPreamp,
                      ),
                    ],
                  ),
                ),
                const Text(
                  "Evens out loudness between songs using the REPLAYGAIN tags written by WORKBENCH > SCAN REPLAYGAIN. Peaks are protected from clipping. Files without tags play unchanged.",
                  style: _hint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
