// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'ghost_avatar.dart';
import '../screens/main_shell.dart';
import '../core/embedding_service.dart';
import '../core/ghost_settings.dart';
import '../core/model_lifecycle.dart';
import '../core/sfx.dart';
import '../core/voice_input.dart';
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
  static final List<_ChatMessage> _sessionMessages = <_ChatMessage>[];
  static const int _maxSessionMessages = 100;

  late final AnimationController _controller;
  late final Animation<double> _panelCurve;
  final Random _rng = Random();
  List<_ChatMessage> get _messages => _sessionMessages;
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  late final ScrollController _scrollController;
  StreamSubscription<String>? _voiceSub;

  GhostChatState _chatState = GhostChatState.collapsed;
  late final GhostBrain _brain = GhostBrain(AppGhostWorld(() => context));
  final VoiceInput _voice = VoiceInput();
  Offset _dragOffset = Offset.zero;
  bool _userInteracted = false;
  bool _inFlight = false;

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
    _sanitizeSessionMessages();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _panelCurve = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    _inputController = TextEditingController();
    _inputFocus = FocusNode()..addListener(_onFocusChange);
    _scrollController = ScrollController();
    _voice.addListener(_onVoicePhaseChanged);

    _voiceSub = _voice.onTranscript.listen((text) {
      if (!mounted) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      final existing = _inputController.text.trim();
      _inputController.text = existing.isEmpty ? trimmed : '$existing $trimmed';
      _inputController.selection = TextSelection.collapsed(offset: _inputController.text.length);
      widget.ghostController.setMood(GhostMood.listening);
      Sfx.play(SfxId.select);
      _inputFocus.requestFocus();
      unawaited(_typewriterSay('HEARD: $trimmed', isGhost: true));
    });

    unawaited(EmbeddingGemmaService.instance.checkNativeAvailability());
    _checkFirstLaunch();
  }

  void _sanitizeSessionMessages() {
    for (int i = 0; i < _sessionMessages.length; i++) {
      final msg = _sessionMessages[i];
      if (msg.isTyping || msg.typingTextNotifier != null) {
        final partial = msg.typingTextNotifier?.value ?? '';
        _sessionMessages[i] = msg.copyWith(
          text: partial.isNotEmpty ? partial : msg.text,
          isTyping: false,
          clearTypingNotifier: true,
        );
      }
    }
  }

  void _appendMessage(_ChatMessage message) {
    _sessionMessages.add(message);
    if (_sessionMessages.length > _maxSessionMessages) {
      _sessionMessages.removeRange(0, _sessionMessages.length - _maxSessionMessages);
    }
  }

  void _finalizeTypingMessage(int id, String finalText) {
    final index = _sessionMessages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    final updated = _sessionMessages[index].copyWith(
      text: finalText,
      isTyping: false,
      clearTypingNotifier: true,
    );
    if (mounted) {
      setState(() {
        _sessionMessages[index] = updated;
      });
    } else {
      _sessionMessages[index] = updated;
    }
  }

  void _disposeNotifierSafely(ValueNotifier<String> notifier) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifier.dispose();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _checkFirstLaunch() async {
    if (!GhostSettings.isReady) await GhostSettings.ready();
    if (!mounted) return;
    if (!GhostSettings.firstLaunchComplete.value && GhostSettings.autoExpand.value && GhostSettings.visible.value) {
      ModelLifecycle.instance.onChatExpanded();
      setState(() {
        _chatState = GhostChatState.expanded;
      });
      _controller.forward();
      await _runFirstLaunchSequence();
    }
  }

  Future<void> _runFirstLaunchSequence() async {
    try {
      for (int i = 0; i < _launchSequence.length; i++) {
        if (!mounted) return;
        final step = _launchSequence[i];
        await _typewriterSay(step.text, isGhost: true);
        if (!mounted) return;
        if (step.isLaugh) {
          await widget.ghostController.glitchLaugh();
        }
        if (!mounted) return;
        await Future.delayed(Duration(milliseconds: step.pauseAfter));
      }
      if (!mounted) return;
      await _startContextualTutorial();
    } finally {
      await GhostSettings.setFirstLaunchComplete();
    }
  }

  Future<void> _startContextualTutorial() async {
    if (!mounted) return;
    final tab = SovereignState.currentTab.value;
    final tutorial = _tutorials[tab] ?? _tutorials[0]!;
    for (final line in tutorial) {
      if (!mounted) return;
      await _typewriterSay(line, isGhost: true);
      await Future.delayed(const Duration(milliseconds: 800));
    }
    if (!mounted) return;
    _addSuggestionsForTab(SovereignState.currentTab.value);
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !_userInteracted && _chatState == GhostChatState.expanded) {
        _toggleCollapse();
      }
    });
  }

  Future<void> _typewriterSay(String text, {bool isGhost = true}) async {
    if (!mounted) return;
    final notifier = ValueNotifier<String>('');
    final message = _ChatMessage(
      text: '',
      isGhost: isGhost,
      isTyping: true,
      typingTextNotifier: notifier,
    );
    setState(() {
      _appendMessage(message);
      _scrollToBottom();
    });
    if (isGhost) widget.ghostController.setMood(GhostMood.talking);

    var completed = false;
    var tickCount = 0;
    try {
      for (int i = 1; i <= text.length; i += 2) {
        if (!mounted) return;
        final end = min(i + 1, text.length);
        notifier.value = text.substring(0, end);
        tickCount++;
        final chunk = text.substring(i - 1, end);
        if (isGhost && chunk.trim().isNotEmpty) {
          if (tickCount.isEven) widget.ghostController.talk();
          if (tickCount.isEven) Sfx.play(SfxId.type);
        }
        await Future.delayed(Duration(milliseconds: 38 + _rng.nextInt(24)));
      }
      if (!mounted) return;
      completed = true;
    } finally {
      final resolved = completed ? text : (notifier.value.isNotEmpty ? notifier.value : text);
      _finalizeTypingMessage(message.id, resolved);
      _disposeNotifierSafely(notifier);
    }
    if (isGhost && mounted) {
      widget.ghostController.setMood(
        _inputFocus.hasFocus && _inputController.text.isNotEmpty ? GhostMood.listening : GhostMood.idle,
      );
      Sfx.play(SfxId.message);
    }
  }

  void _onInputChanged(String text) {
    widget.ghostController.setMood(text.trim().isEmpty ? GhostMood.idle : GhostMood.listening);
  }

  Future<void> _onMicTap() async {
    if (_voice.isBusy && !_voice.isListening) {
      await _voice.cancel();
      return;
    }
    await _voice.toggle();
  }

  void _onVoicePhaseChanged() {
    if (!mounted) return;
    switch (_voice.phase) {
      case VoicePhase.preparing:
      case VoicePhase.listening:
        widget.ghostController.setMood(GhostMood.listening);
        break;
      case VoicePhase.stopping:
      case VoicePhase.modelLoading:
      case VoicePhase.transcribing:
        widget.ghostController.setMood(GhostMood.thinking);
        break;
      case VoicePhase.completed:
      case VoicePhase.idle:
      case VoicePhase.failed:
      case VoicePhase.canceled:
        if (!_inFlight) {
          widget.ghostController.setMood(
            _inputFocus.hasFocus && _inputController.text.trim().isNotEmpty ? GhostMood.listening : GhostMood.idle,
          );
        }
        break;
    }
  }

  void _onFocusChange() {
    if (!_inputFocus.hasFocus && _inputController.text.trim().isEmpty) {
      widget.ghostController.setMood(GhostMood.idle);
    }
  }

  void _addSuggestionsForTab(int tab) {
    _showSuggestionChips([..._brain.suggestionsFor(tab)]);
  }

  void _showSuggestionChips(List<String> chips) {
    setState(() {
      _appendMessage(_ChatMessage(text: '', chips: chips, isGhost: true));
      _scrollToBottom();
    });
  }

  Future<void> _handleUserInput(String text) async {
    if (text.trim().isEmpty) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      _userInteracted = true;
      _inputController.clear();
      Sfx.play(SfxId.select);
      _addMessage(_ChatMessage(text: text, isGhost: false));
      widget.ghostController.setMood(GhostMood.thinking);
      await Future.delayed(Duration(milliseconds: 380 + _rng.nextInt(320)));
      if (!mounted) return;
      await _processUserQuery(text);
    } catch (e) {
      debugPrint('GHOST: command failed: $e');
      if (mounted) await _typewriterSay('COMMAND FAILED: $e', isGhost: true);
    } finally {
      _inFlight = false;
      if (mounted) widget.ghostController.setMood(GhostMood.idle);
    }
  }

  Future<void> _processUserQuery(String query) async {
    GhostReply reply;
    try {
      reply = await _brain.respond(query);
    } catch (e) {
      debugPrint('GHOST: _brain.respond threw: $e');
      reply = GhostReply("ERROR: $e", tone: GhostTone.sarcastic);
    }
    if (!mounted) return;
    final emotion = switch (reply.tone) {
      GhostTone.happy => GhostEmotion.happy,
      GhostTone.sarcastic => GhostEmotion.sarcastic,
      GhostTone.info => GhostEmotion.serious,
    };
    widget.ghostController.setEmotion(emotion);
    await _typewriterSay(reply.text, isGhost: true);
    if (!mounted) return;
    if (reply.laugh) {
      await widget.ghostController.glitchLaugh();
      if (!mounted) return;
    }
    if (reply.chips.isNotEmpty) {
      _showSuggestionChips(reply.chips);
    }
    if (reply.hide) {
      await _dismissGhost();
    }
  }

  Future<void> _dismissGhost() async {
    ModelLifecycle.instance.onChatCollapsed();
    if (mounted && _chatState != GhostChatState.collapsed) {
      setState(() => _chatState = GhostChatState.collapsed);
      _controller.reverse();
      _inputFocus.unfocus();
    }
    await widget.ghostController.dematerialize();
    try {
      await GhostSettings.setVisible(false);
    } catch (e) {
      debugPrint('GHOST: could not persist visibility: $e');
    }
  }

  void _addMessage(_ChatMessage message) {
    setState(() {
      _appendMessage(message);
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _toggleCollapse() {
    _userInteracted = true;
    widget.ghostController.poke();
    final willExpand = _chatState == GhostChatState.collapsed;
    Sfx.play(willExpand ? SfxId.open : SfxId.close);
    setState(() {
      _chatState = willExpand ? GhostChatState.expanded : GhostChatState.collapsed;
    });
    if (willExpand) {
      ModelLifecycle.instance.onChatExpanded();
      _controller.forward();
      widget.ghostController.setMood(_inputController.text.isNotEmpty ? GhostMood.listening : GhostMood.idle);
      if (_messages.isEmpty) {
        _startContextualTutorial();
      } else {
        _scrollToBottom();
      }
    } else {
      ModelLifecycle.instance.onChatCollapsed();
      _controller.reverse();
      _inputFocus.unfocus();
      widget.ghostController.setMood(GhostMood.idle);
    }
  }

  void _onDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
  }

  @override
  void dispose() {
    _sanitizeSessionMessages();
    ModelLifecycle.instance.onChatCollapsed();
    _voice.removeListener(_onVoicePhaseChanged);
    _voiceSub?.cancel();
    _voice.dispose();
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
                      size: 76,
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
    final panelBody = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: themeColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "GHOST IN THE MACHINE",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11.5, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 0.6),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: EmbeddingGemmaService.instance.nativeActiveNotifier,
                builder: (context, nativeActive, _) {
                  final badgeColor = nativeActive ? Colors.cyanAccent : themeColor.withValues(alpha: 0.7);
                  return Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.65), width: 0.8),
                    ),
                    child: Text(
                      nativeActive ? "GEMMA" : "256D",
                      style: TextStyle(
                        fontFamily: 'ShareTechMono',
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 18),
                tooltip: "CLOSE GHOST",
                onPressed: () {
                  unawaited(_dismissGhost());
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
          child: RepaintBoundary(
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                        fillColor: Colors.black.withValues(alpha: 0.45),
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
                  _buildMicButton(themeColor),
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
              _buildVoiceStatus(themeColor),
            ],
          ),
        ),
      ],
    );

    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [BoxShadow(color: themeColor.withValues(alpha: 0.26 * a), blurRadius: 20, spreadRadius: 1)],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: themeColor.withValues(alpha: 0.72 * a), width: 1.2),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF0A0C12), themeColor, 0.14)!.withValues(alpha: 0.94 * a),
                    const Color(0xFF07080D).withValues(alpha: 0.95 * a),
                    const Color(0xFF040508).withValues(alpha: 0.97 * a),
                  ],
                ),
              ),
              child: a >= 0.995 ? panelBody : Opacity(opacity: a, child: panelBody),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicButton(Color themeColor) {
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final listening = _voice.isListening;
        final busy = _voice.isBusy && !listening;
        final blocked = _voice.micBlocked;
        final tint = listening
            ? Colors.redAccent
            : (busy || blocked ? Colors.amberAccent : themeColor);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: tint.withValues(alpha: listening ? 0.95 : 0.45),
              width: listening ? 1.8 : 1,
            ),
            color: listening ? Colors.redAccent.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.25),
          ),
          child: IconButton(
            icon: Icon(
              listening
                  ? Icons.stop
                  : (busy ? Icons.close : (blocked ? Icons.mic_off : Icons.mic_none)),
              color: tint,
              size: 18,
            ),
            onPressed: _onMicTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            tooltip: blocked
                ? 'MIC BLOCKED - OPEN APP SETTINGS'
                : (busy ? 'CANCEL VOICE QUERY' : (listening ? 'STOP AND TRANSCRIBE' : 'VOICE QUERY')),
          ),
        );
      },
    );
  }

  Widget _buildVoiceStatus(Color themeColor) {
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final s = _voice.status;
        if (s.isEmpty) return const SizedBox.shrink();
        final showBar = (_voice.phase == VoicePhase.preparing || _voice.phase == VoicePhase.modelLoading) && _voice.progress > 0;
        final isError = _voice.phase == VoicePhase.failed || _voice.phase == VoicePhase.canceled;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s,
                style: TextStyle(
                  fontFamily: 'VT323',
                  fontSize: 12,
                  color: isError ? Colors.redAccent : themeColor,
                ),
              ),
              if (showBar)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _voice.progress,
                      minHeight: 3,
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
          color: isGhost ? Colors.black.withValues(alpha: 0.62) : themeColor.withValues(alpha: 0.85),
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
            if (msg.isTyping && msg.typingTextNotifier != null)
              ValueListenableBuilder<String>(
                valueListenable: msg.typingTextNotifier!,
                builder: (context, val, _) => Text(
                  '${val}_',
                  style: TextStyle(
                    fontFamily: isGhost ? 'VT323' : 'ShareTechMono',
                    fontSize: isGhost ? 15 : 12,
                    color: isGhost ? Colors.white : Colors.black,
                    height: 1.25,
                  ),
                ),
              )
            else
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
  final ValueNotifier<String>? typingTextNotifier;

  _ChatMessage({
    int? id,
    required this.text,
    required this.isGhost,
    this.isTyping = false,
    this.chips,
    this.typingTextNotifier,
  }) : id = id ?? ++_counter;

  _ChatMessage copyWith({
    String? text,
    bool? isTyping,
    bool clearTypingNotifier = false,
  }) =>
      _ChatMessage(
        id: id,
        text: text ?? this.text,
        isGhost: isGhost,
        isTyping: isTyping ?? this.isTyping,
        chips: chips,
        typingTextNotifier: clearTypingNotifier ? null : typingTextNotifier,
      );
}

class _LaunchStep {
  final String text;
  final int pauseAfter;
  final bool isLaugh;

  _LaunchStep({required this.text, required this.pauseAfter, this.isLaugh = false});
}
