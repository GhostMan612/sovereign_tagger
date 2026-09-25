// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ghost_avatar.dart';
import '../screens/main_shell.dart';
import '../core/ghost_settings.dart';
import '../core/sfx.dart';
import '../services/ghost_classifier.dart';

enum GhostChatState { collapsed, expanded, typing, listening }

class GhostChatOverlay extends StatefulWidget {
  final ValueNotifier<Color> accentColor;
  final GhostAvatarController ghostController;
  final GlobalKey<GhostAvatarState>? ghostKey;
  final VoidCallback? onClose;

  const GhostChatOverlay({
    super.key,
    required this.accentColor,
    required this.ghostController,
    this.ghostKey,
    this.onClose,
  });

  @override
  State<GhostChatOverlay> createState() => _GhostChatOverlayState();
}

class _GhostChatOverlayState extends State<GhostChatOverlay> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _panelCurve;
  final Random _rng = Random();
  late final List<_ChatMessage> _messages;
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  late final ScrollController _scrollController;

  GhostChatState _chatState = GhostChatState.collapsed;
  late final GhostClassifier _classifier;
  Offset _dragOffset = Offset.zero;
  bool _userInteracted = false;

  final List<_LaunchStep> _launchSequence = [
    _LaunchStep(text: "Welcome to...", pauseAfter: 800),
    _LaunchStep(text: "The Machine", pauseAfter: 600),
    _LaunchStep(text: "Shall We Activate SkyNet?", pauseAfter: 1000),
    _LaunchStep(text: "Just Kidding... hahaha!", pauseAfter: 500, isLaugh: true),
  ];

  final Map<int, List<String>> _tutorials = {
    0: [
      "You're in GRABBER. Paste a link, SHARE one into the app from YouTube, or HUNT by artist + title.",
      "Finished downloads become cards: fix title/artist/file name, then PLAY, SAVE TO MUSIC, SEND TO FORGE or DISCARD. Nothing moves on its own.",
      "Audio defaults to the original M4A stream (no re-encode). MP3 320K and AS-IS are in the mode menu. Silent Facebook videos auto-heal.",
    ],
    1: [
      "FORGE is the tag editor. Mount any song (or EDIT IN FORGE from Library/Player). Nothing touches the file until SAVE.",
      "SEARCH METADATA / IDENTIFY show a review sheet: tick what to change, then APPLY. SAVE & FIX ORIGINAL rewrites the song in place.",
      "PLAY IN PLAYER previews the song. FIND pulls lyrics, SYNC stamps karaoke timings that get embedded on save.",
    ],
    2: [
      "BATCH fixes many songs at once. Load FROM LIBRARY, then EXECUTE. Android asks once for permission to modify them.",
      "Confident matches are fixed in place. Unsure ones land in REVIEW — tap one to finish it in the FORGE.",
      "Long-press a track to re-identify it from scratch. MIXTAPE JOIN glues PROCESSED mp3s losslessly.",
    ],
    3: [
      "WORKBENCH DSP: 15-band EQ (AutoEq), LUFS -14, Whisper transcribe, PCM LOSSLESS 48k/16-bit WAV.",
      "Pitch modes: VARISPEED (pitch+tempo), RUBBERBAND (pitch only), ATEMPO (tempo only).",
      "REPLAYGAIN scan writes tags the PLAYER uses to even out loudness.",
    ],
    4: [
      "LIBRARY: every song on the phone. SONGS, ALBUMS, ARTISTS, FOLDERS, PLAYLISTS and NEW. Search filters live.",
      "Tap a song to play from there. PLAY ALL / SHUFFLE on any list. Long-press for play next, queue, favorite, playlist, FORGE.",
      "Favorites and Recently Played live under PLAYLISTS.",
    ],
    5: [
      "PLAYER: tap the mini-player for full screen. Pinch-zoom artwork, double-tap to seek ±10s, swipe to skip.",
      "Queue: drag to reorder, swipe to remove, save as playlist. Lyrics button shows embedded karaoke lyrics or fetches them.",
      "Tune icon = EQUALIZER (heard live). Merge icon = PLAYBACK ENGINE (fades + ReplayGain).",
    ],
    6: [
      "SETTINGS: Genius/ACR keys, color picker, FFmpeg probe, cache purge, backup/restore.",
      "Keys are optional now: metadata search and lyrics work without Genius, ACR is only for fingerprinting.",
      "Ghost Tutorial: reduce-motion, auto-expand, visibility toggle, reset first-launch.",
    ],
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _panelCurve = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    _messages = [];
    _inputController = TextEditingController();
    _inputFocus = FocusNode()..addListener(_onFocusChange);
    _scrollController = ScrollController();
    _classifier = GhostClassifier();

    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    if (!GhostSettings.firstLaunchComplete.value && GhostSettings.autoExpand.value && GhostSettings.visible.value) {
      setState(() {
        _chatState = GhostChatState.expanded;
      });
      _controller.forward();
      await _runFirstLaunchSequence();
    }
  }

  Future<void> _runFirstLaunchSequence() async {
    for (int i = 0; i < _launchSequence.length; i++) {
      final step = _launchSequence[i];
      await _typewriterSay(step.text, isGhost: true);
      if (step.isLaugh) {
        await widget.ghostController.glitchLaugh();
      }
      await Future.delayed(Duration(milliseconds: step.pauseAfter));
    }
    await GhostSettings.setFirstLaunchComplete();
    await _startContextualTutorial();
  }

  Future<void> _startContextualTutorial() async {
    final tab = SovereignState.currentTab.value;
    final tutorial = _tutorials[tab] ?? _tutorials[0]!;
    for (final line in tutorial) {
      await _typewriterSay(line, isGhost: true);
      await Future.delayed(const Duration(milliseconds: 800));
    }
    _addSuggestionsForTab(SovereignState.currentTab.value);
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !_userInteracted && _chatState == GhostChatState.expanded) {
        _toggleCollapse();
      }
    });
  }

  Future<void> _typewriterSay(String text, {bool isGhost = true}) async {
    final message = _ChatMessage(text: '', isGhost: isGhost, isTyping: true);
    setState(() {
      _messages.add(message);
      _scrollToBottom();
    });
    if (isGhost) widget.ghostController.setMood(GhostMood.talking);

    for (int i = 1; i <= text.length; i++) {
      if (!mounted) return;
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index < 0) break;
      setState(() => _messages[index] = _messages[index].copyWith(text: text.substring(0, i)));
      final char = text[i - 1];
      if (isGhost && char.trim().isNotEmpty) {
        widget.ghostController.talk();
        if (i.isEven) Sfx.play(SfxId.type);
      }
      await Future.delayed(Duration(milliseconds: 22 + _rng.nextInt(34)));
    }
    if (!mounted) return;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) setState(() => _messages[index] = _messages[index].copyWith(text: text, isTyping: false));
    if (isGhost) {
      widget.ghostController.setMood(_inputFocus.hasFocus && _inputController.text.isNotEmpty ? GhostMood.listening : GhostMood.idle);
      Sfx.play(SfxId.message);
    }
  }

  void _onInputChanged(String text) {
    widget.ghostController.setMood(text.trim().isEmpty ? GhostMood.idle : GhostMood.listening);
  }

  void _onFocusChange() {
    if (!_inputFocus.hasFocus && _inputController.text.trim().isEmpty) {
      widget.ghostController.setMood(GhostMood.idle);
    }
  }

  void _addSuggestionsForTab(int tab) {
    final suggestions = <String>[
      if (tab == 0) ...["Search YouTube", "Download MP3 320K", "SOURCE COPY mode"],
      if (tab == 1) ...["Load file to Forge", "Export with tags", "Karaoke mode"],
      if (tab == 2) ...["Scan MediaStore", "Run batch", "Mixtape join"],
      if (tab == 3) ...["ReplayGain scan", "Whisper transcribe", "15-band EQ"],
      if (tab == 4) ...["Load queue", "Shuffle all", "Sleep timer 30m"],
      if (tab == 5) ...["Playback engine", "EQ presets", "Gapless audit"],
      if (tab == 6) ...["How to get Genius API key", "How to get ACRCloud keys", "Open Genius signup", "Open ACR console"],
      "Help", "Settings", "Hide ghost",
    ];
    _showSuggestionChips(suggestions);
  }

  void _showSuggestionChips(List<String> chips) {
    setState(() {
      _messages.add(_ChatMessage(text: '', chips: chips, isGhost: true));
      _scrollToBottom();
    });
  }

  Future<void> _launchUrl(String url) async {
    try {
      await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('openUrl', {'url': url});
      if (mounted) {
        await _typewriterSay("Registration page launched. Grab the key, then SETTINGS > paste > WRITE TO KERNEL.", isGhost: true);
      }
    } catch (_) {
      if (mounted) await _typewriterSay("Browser fault. Open the URL manually from Settings.", isGhost: true);
    }
  }

  Future<void> _handleUserInput(String text) async {
    if (text.trim().isEmpty) return;
    _userInteracted = true;
    _inputController.clear();
    Sfx.play(SfxId.select);
    _addMessage(_ChatMessage(text: text, isGhost: false));
    widget.ghostController.setMood(GhostMood.thinking);
    await Future.delayed(Duration(milliseconds: 380 + _rng.nextInt(320)));
    if (!mounted) return;
    widget.ghostController.setMood(GhostMood.idle);
    await _processUserQuery(text);
  }

  Future<void> _processUserQuery(String query) async {
    final lower = query.toLowerCase();

    if (lower.contains('hide') || lower.contains('go away') || lower.contains('dismiss')) {
      await _toggleCollapse();
      return;
    }
    if (lower.contains('laugh') || lower.contains('joke') || lower.contains('skynet')) {
      await widget.ghostController.glitchLaugh();
      await _typewriterSay("hahaha! *glitches maniacally*", isGhost: true);
      _addSuggestionsForTab(SovereignState.currentTab.value);
      return;
    }

    if (lower.contains('open genius') || lower.contains('genius signup') || lower.contains('genius registration')) {
      await _launchUrl('https://genius.com/api-clients');
      return;
    }
    if (lower.contains('open acr') || lower.contains('acr signup') || lower.contains('acr registration') || lower.contains('acr console')) {
      await _launchUrl('https://console.acrcloud.com/');
      return;
    }
    if (lower.contains('genius key') || lower.contains('genius api') || lower.contains('lyrics key') || lower.contains('client access token')) {
      await widget.ghostController.glitchLaugh();
      await _typewriterSay("GENIUS KEY RITUAL: 1) Say 'OPEN GENIUS' and I launch the client page. 2) New API Client → name it anything → SAVE. 3) Copy the CLIENT ACCESS TOKEN. 4) SETTINGS > GENIUS API > paste > WRITE TO KERNEL. Without it: no lyrics, no album art.", isGhost: true);
      _addSuggestionsForTab(SovereignState.currentTab.value);
      return;
    }
    if (lower.contains('acr key') || lower.contains('acrcloud key') || lower.contains('fingerprint key') || lower.contains('acr api')) {
      await widget.ghostController.glitchLaugh();
      await _typewriterSay("ACRCLOUD RITUAL: 1) Say 'OPEN ACR' — I launch the console. 2) Free account → Audio & Video Recognition → Create Project → Recorded Audio → ACRCloud Music bucket. 3) Copy HOST + ACCESS KEY + ACCESS SECRET. 4) SETTINGS > ACRCLOUD > paste all three > WRITE TO KERNEL. Without it, fingerprinting is off — BATCH falls back to file names.", isGhost: true);
      _addSuggestionsForTab(SovereignState.currentTab.value);
      return;
    }

    String response = "";
    final intent = _classifier.classify(query);
    if (intent != null) {
      response = await _replyForIntent(intent);
    } else if (lower.contains('grab') || lower.contains('download') || lower.contains('youtube')) {
      response = await _getContextualReply(0);
    } else if (lower.contains('tag') || lower.contains('forge') || lower.contains('export') || lower.contains('karaoke')) {
      response = await _getContextualReply(1);
    } else if (lower.contains('pipe') || lower.contains('batch') || lower.contains('acr') || lower.contains('mixtape')) {
      response = await _getContextualReply(2);
    } else if (lower.contains('dsp') || lower.contains('eq') || lower.contains('loudnorm') || lower.contains('whisper') || lower.contains('pcm') || lower.contains('denoise')) {
      response = await _getContextualReply(3);
    } else if (lower.contains('librar') || lower.contains('browse') || lower.contains('album') || lower.contains('artist')) {
      response = await _getContextualReply(4);
    } else if (lower.contains('play') || lower.contains('queue') || lower.contains('speed') || lower.contains('sleep') || lower.contains('crossfade') || lower.contains('gapless')) {
      response = await _getContextualReply(5);
    } else if (lower.contains('setting') || lower.contains('color') || lower.contains('backup') || lower.contains('ghost')) {
      response = await _getContextualReply(6);
    } else if (lower.contains('help') || lower.contains('what') || lower.contains('how')) {
      response = "I'm your ghost in the machine. Ask me about GRABBER, FORGE, BATCH, WORKBENCH, LIBRARY, PLAYER, or SETTINGS. Or just tap a suggestion chip below.";
    } else {
      response = "Signal unclear. Try: 'how do I download', 'what is forge', 'replaygain scan', 'crossfade 5s', or tap a chip below.";
    }

    await _typewriterSay(response, isGhost: true);
    _addSuggestionsForTab(SovereignState.currentTab.value);
  }

  Future<String> _replyForIntent(String intent) async {
    switch (intent) {
      case 'GRABBER':
        return _getContextualReply(0);
      case 'FORGE':
        return _getContextualReply(1);
      case 'PIPELINE':
        return _getContextualReply(2);
      case 'WORKBENCH':
      case 'WHISPER':
      case 'EQ':
      case 'REPLAYGAIN':
        return _getContextualReply(3);
      case 'LIBRARY':
        return _getContextualReply(4);
      case 'PLAYER':
      case 'CROSSFADE':
      case 'GAPLESS':
        return _getContextualReply(5);
      case 'SETTINGS':
      case 'BACKUP':
        return _getContextualReply(6);
      case 'WIDGET':
        return _getContextualReply(4);
      default:
        return _getContextualReply(SovereignState.currentTab.value);
    }
  }

  Future<String> _getContextualReply(int tab) async {
    final tutorial = _tutorials[tab] ?? _tutorials[0]!;
    return tutorial[Random().nextInt(tutorial.length)];
  }

  void _addMessage(_ChatMessage message) {
    setState(() {
      _messages.add(message);
      _scrollToBottom();
    });
  }

void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleCollapse() async {
    _userInteracted = true;
    if (_chatState == GhostChatState.expanded) {
      Sfx.play(SfxId.close);
      _inputFocus.unfocus();
      widget.ghostController.setMood(GhostMood.idle);
      setState(() => _chatState = GhostChatState.collapsed);
      await _controller.reverse();
    } else {
      Sfx.play(SfxId.open);
      widget.ghostController.setEmotion(GhostEmotion.happy);
      setState(() => _chatState = GhostChatState.expanded);
      await _controller.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      _inputFocus.requestFocus();
    }
  }

  void _onDrag(DragUpdateDetails d) {
    final mq = MediaQuery.of(context);
    setState(() {
      _dragOffset = Offset(
        (_dragOffset.dx + d.delta.dx).clamp(-(mq.size.width - 96), 0.0),
        (_dragOffset.dy + d.delta.dy).clamp(-(mq.size.height - 220), 60.0),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: widget.accentColor,
      builder: (context, themeColor, child) {
        return AnimatedBuilder(
          animation: _panelCurve,
          builder: (context, child) {
            final t = _panelCurve.value;
            final panelVisible = _chatState == GhostChatState.expanded || _controller.value > 0;
            return Transform.translate(
              offset: _dragOffset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (panelVisible)
                    Transform.translate(
                      offset: Offset(0, 18 * (1 - t)),
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * t,
                        alignment: Alignment.bottomRight,
                        child: _buildPanel(themeColor, t.clamp(0.0, 1.0)),
                      ),
                    ),
                  if (panelVisible) const SizedBox(height: 6),
                  GestureDetector(
                    onPanUpdate: _onDrag,
                    child: GhostAvatar(
                      key: widget.ghostKey,
                      size: 64,
                      accentColor: widget.accentColor,
                      onTap: _toggleCollapse,
                      onLongPress: () => widget.ghostController.glitchLaugh(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPanel(Color themeColor, double a) {
    final radius = BorderRadius.circular(16);
    final width = min(300.0, MediaQuery.sizeOf(context).width - 32);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 400),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [BoxShadow(color: themeColor.withValues(alpha: 0.28 * a), blurRadius: 22, spreadRadius: 1)],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 0.01 + 16 * a, sigmaY: 0.01 + 16 * a),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: themeColor.withValues(alpha: 0.7 * a), width: 1.2),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    themeColor.withValues(alpha: 0.14 * a),
                    Colors.black.withValues(alpha: 0.38 * a),
                    Colors.black.withValues(alpha: 0.52 * a),
                  ],
                ),
              ),
              child: Opacity(
                opacity: a,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, color: themeColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "GHOST IN THE MACHINE",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 18),
                            tooltip: "CLOSE GHOST",
                            onPressed: () {
                              Sfx.play(SfxId.close);
                              if (_chatState == GhostChatState.expanded) {
                                _controller.reverse().then((_) {
                                  if (mounted) _chatState = GhostChatState.collapsed;
                                });
                              }
                              GhostSettings.setVisible(false);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: themeColor, size: 18),
                            tooltip: "MINIMIZE",
                            onPressed: _toggleCollapse,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 12), color: themeColor.withValues(alpha: 0.25)),
                    Flexible(
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[_messages.length - 1 - index];
                          final child = msg.chips != null ? _buildSuggestionChips(msg.chips!, themeColor) : _buildMessageBubble(msg, themeColor);
                          return _Entrance(key: ValueKey(msg.id), fromLeft: msg.isGhost, child: child);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _inputFocus,
                              onChanged: _onInputChanged,
                              cursorColor: themeColor,
                              style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: "QUERY THE GHOST...",
                                hintStyle: const TextStyle(fontFamily: 'VT323', color: Colors.white38, fontSize: 14),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.35),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: themeColor.withValues(alpha: 0.45)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: themeColor, width: 1.6),
                                ),
                              ),
                              onSubmitted: _handleUserInput,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ),
                          const SizedBox(width: 6),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: themeColor.withValues(alpha: 0.7)),
                              color: themeColor.withValues(alpha: 0.12),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.send, color: themeColor, size: 18),
                              onPressed: () => _handleUserInput(_inputController.text),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, Color themeColor) {
    final isGhost = msg.isGhost;
    return Align(
      alignment: isGhost ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: isGhost ? Colors.black.withValues(alpha: 0.35) : themeColor.withValues(alpha: 0.85),
          border: Border.all(color: isGhost ? themeColor.withValues(alpha: 0.5) : themeColor, width: 1),
          borderRadius: BorderRadius.circular(12).copyWith(
            bottomLeft: isGhost ? const Radius.circular(2) : const Radius.circular(12),
            bottomRight: isGhost ? const Radius.circular(12) : const Radius.circular(2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGhost) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: themeColor, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    msg.isTyping ? "GHOST ▸ TRANSMITTING" : "GHOST",
                    style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, fontWeight: FontWeight.bold, color: themeColor),
                  ),
                ],
              ),
              const SizedBox(height: 2),
            ],
            Text(
              msg.isTyping ? '${msg.text}_' : msg.text,
              style: TextStyle(
                fontFamily: isGhost ? 'VT323' : 'ShareTechMono',
                fontSize: isGhost ? 15 : 12,
                color: isGhost ? Colors.white : Colors.black,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChips(List<String> chips, Color themeColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: chips
              .map((chip) => ActionChip(
                    label: Text(chip, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
                    backgroundColor: themeColor.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    onPressed: () => _handleUserInput(chip),
                    shape: const StadiumBorder(),
                    side: BorderSide(color: themeColor.withValues(alpha: 0.6)),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  final Widget child;
  final bool fromLeft;

  const _Entrance({super.key, required this.child, required this.fromLeft});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  late final Animation<double> _curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(widget.fromLeft ? -0.08 : 0.08, 0.15), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

class _ChatMessage {
  static int _counter = 0;

  final int id;
  final String text;
  final bool isGhost;
  final bool isTyping;
  final List<String>? chips;

  _ChatMessage({
    int? id,
    required this.text,
    required this.isGhost,
    this.isTyping = false,
    this.chips,
  }) : id = id ?? ++_counter;

  _ChatMessage copyWith({String? text, bool? isTyping}) =>
      _ChatMessage(id: id, text: text ?? this.text, isGhost: isGhost, isTyping: isTyping ?? this.isTyping, chips: chips);
}

class _LaunchStep {
  final String text;
  final int pauseAfter;
  final bool isLaugh;

  _LaunchStep({required this.text, required this.pauseAfter, this.isLaugh = false});
}
