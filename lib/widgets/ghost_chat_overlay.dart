// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'ghost_avatar.dart';
import '../screens/main_shell.dart';
import '../core/ghost_settings.dart';
import '../core/sfx.dart';
import '../services/ghost_brain.dart';
import '../services/ghost_world.dart';

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
  late final GhostBrain _brain = GhostBrain(AppGhostWorld(() => context));
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
    _showSuggestionChips([..._brain.suggestionsFor(tab), 'Hide ghost']);
  }

  void _showSuggestionChips(List<String> chips) {
    setState(() {
      _messages.add(_ChatMessage(text: '', chips: chips, isGhost: true));
      _scrollToBottom();
    });
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
    final reply = await _brain.respond(query);
    if (!mounted) return;
    switch (reply.tone) {
      case GhostTone.happy:
        widget.ghostController.setEmotion(GhostEmotion.happy);
        break;
      case GhostTone.sarcastic:
        widget.ghostController.setEmotion(GhostEmotion.sarcastic);
        break;
      case GhostTone.info:
        break;
    }
    if (reply.laugh) unawaited(widget.ghostController.glitchLaugh());
    await _typewriterSay(reply.text, isGhost: true);
    if (!mounted) return;
    if (reply.chips.isNotEmpty) _showSuggestionChips(reply.chips);
    if (reply.hide && _chatState == GhostChatState.expanded) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted && _chatState == GhostChatState.expanded) await _toggleCollapse();
    }
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
