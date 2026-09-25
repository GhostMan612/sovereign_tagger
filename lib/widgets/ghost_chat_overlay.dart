// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ghost_avatar.dart';
import '../screens/main_shell.dart';
import '../core/ghost_settings.dart';
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
  late final AnimationController _typewriterController;
  late final AnimationController _bubbleController;
  late final List<_ChatMessage> _messages;
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  late final ScrollController _scrollController;

  GhostChatState _chatState = GhostChatState.collapsed;
  String _currentTypingText = '';
  Timer? _typewriterTimer;
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
      "You're in GRABBER — the downloader. Tap SEARCH, type a query, pick a format, hit DOWNLOAD.",
      "EXPORT AS: MP3 320K (default) or SOURCE COPY (webm/opus/m4a passthrough).",
      "Facebook videos often lack audio — GRABBER auto-heals with bestaudio companion.",
    ],
    1: [
      "FORGE is the ID3 editor. Load a file, edit tags, EXPORT preserves container (mp3/flac/wav/m4a/ogg/opus).",
      "EJECT = cache-only delete with confirm dialog. Your originals are never touched.",
      "KARAOKE launches isolated player with transport bar + tempo warp. LRC sidecar supported.",
    ],
    2: [
      "PIPELINE batch processes: GHOST → PARTIAL (ACR) → PRISTINE (Genius) → PROCESSED.",
      "CANCEL halts the batch. FAILED items can RETRY (re-buckets to GHOST/PARTIAL).",
      "MIXTAPE JOIN: lossless concat of PROCESSED mp3s → single file in Music.",
    ],
    3: [
      "WORKBENCH DSP: 15-band EQ (AutoEq), LUFS -14, Whisper transcribe, PCM LOSSLESS 48k/16-bit WAV.",
      "Pitch modes: VARISPEED (pitch+tempo), RUBBERBAND (pitch only), ATEMPO (tempo only).",
      "REPLAYGAIN scan writes TXXX tags. The tune icon up top opens EQ PRESETS.",
    ],
    4: [
      "LIBRARY: Browse MediaStore by ALBUM/ARTIST/FOLDER. Search filters in real-time.",
      "Tap any track → replaces queue, switches to PLAYER tab.",
      "Artwork decoded from base64 tags. Long-press for queue actions.",
    ],
    5: [
      "PLAYER: Mini-player + theater mode. Pinch-zoom artwork (1→3x). Double-tap = ±10s seek.",
      "Speed 0.5x–2x, sleep timer, shuffle/repeat. Queue persists across restarts.",
      "Merge icon opens PLAYBACK ENGINE (crossfade/gapless). Tune icon opens 15-BAND EQ PRESETS.",
    ],
    6: [
      "SETTINGS: Genius/ACR keys, color picker, FFmpeg probe, cache purge, backup/restore.",
      "Playback lives on the PLAYER tab now — crossfade/gapless/EQ presets live there.",
      "Ghost Tutorial: reduce-motion, auto-expand, visibility toggle, reset first-launch.",
    ],
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _typewriterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 50));
    _bubbleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _messages = [];
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
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
    _currentTypingText = '';
    final message = _ChatMessage(text: '', isGhost: isGhost, isTyping: true);
    setState(() {
      _messages.add(message);
      _scrollToBottom();
    });

    for (int i = 0; i < text.length; i++) {
      if (!mounted) return;
      _currentTypingText += text[i];
      _messages.last = _ChatMessage(text: _currentTypingText, isGhost: isGhost, isTyping: true);
      setState(() {});
      await Future.delayed(Duration(milliseconds: 30 + Random().nextInt(50)));
    }
    if (mounted) {
      _messages.last = _ChatMessage(text: text, isGhost: isGhost, isTyping: false);
      setState(() {});
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

  void _handleUserInput(String text) {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    _addMessage(_ChatMessage(text: text, isGhost: false));
    _processUserQuery(text);
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
      await _typewriterSay("ACRCLOUD RITUAL: 1) Say 'OPEN ACR' — I launch the console. 2) Free account → Audio & Video Recognition → Create Project → Recorded Audio → ACRCloud Music bucket. 3) Copy HOST + ACCESS KEY + ACCESS SECRET. 4) SETTINGS > ACRCLOUD > paste all three > WRITE TO KERNEL. Without it: Pipeline identification is blind.", isGhost: true);
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
      response = "I'm your ghost in the machine. Ask me about GRABBER, FORGE, PIPELINE, WORKBENCH, LIBRARY, PLAYER, or SETTINGS. Or just tap a suggestion chip below.";
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
      setState(() => _chatState = GhostChatState.collapsed);
      await _controller.reverse();
    } else {
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
    _typewriterController.dispose();
    _bubbleController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: widget.accentColor,
      builder: (context, themeColor, child) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final panelVisible = _chatState == GhostChatState.expanded || _controller.value > 0;

            return Transform.translate(
              offset: _dragOffset,
child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (panelVisible)
                  Transform.scale(
                    scale: 0.8 + 0.2 * _controller.value,
                    alignment: Alignment.bottomRight,
                    child: Opacity(
                      opacity: _controller.value.clamp(0.0, 1.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 8, right: 2, bottom: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome, color: themeColor, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      "GHOST IN THE MACHINE",
                                      style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: themeColor),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 18),
                                      tooltip: "CLOSE GHOST",
                                      onPressed: () {
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
                              Flexible(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  reverse: true,
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = _messages[_messages.length - 1 - index];
                                    if (msg.chips != null) {
                                      return _buildSuggestionChips(msg.chips!, themeColor);
                                    }
                                    return _buildMessageBubble(msg, themeColor);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _inputController,
                                        focusNode: _inputFocus,
                                        style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(
                                          hintText: "QUERY THE GHOST...",
                                          hintStyle: TextStyle(fontFamily: 'VT323', color: Colors.white38, fontSize: 12),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                        onSubmitted: _handleUserInput,
                                        textCapitalization: TextCapitalization.sentences,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.send, color: themeColor, size: 20),
                                      onPressed: () => _handleUserInput(_inputController.text),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    ),
                                  ],
                                ),
                              ),
                             ],
                           ),
                         ),
                       ),
                     ),
                 GestureDetector(
                  onPanUpdate: _onDrag,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - _controller.value)),
                    child: Opacity(
                      opacity: 1.0,
                      child: GhostAvatar(
                        key: widget.ghostKey,
                        size: 64,
                        accentColor: widget.accentColor,
                        onTap: _toggleCollapse,
                        onLongPress: () {
                          widget.ghostController.glitchLaugh();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, Color themeColor) {
    final isGhost = msg.isGhost;
    return Align(
      alignment: isGhost ? Alignment.centerLeft : Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _bubbleController,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: isGhost ? Colors.black : themeColor.withAlpha(200),
              border: Border.all(color: isGhost ? themeColor.withAlpha(150) : themeColor, width: 1),
              borderRadius: BorderRadius.circular(12).copyWith(
                bottomLeft: isGhost ? const Radius.circular(2) : const Radius.circular(12),
                bottomRight: isGhost ? const Radius.circular(12) : const Radius.circular(2),
              ),
              boxShadow: isGhost ? [
                BoxShadow(color: themeColor.withAlpha(50), blurRadius: 8, spreadRadius: 1),
              ] : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGhost) ...[
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: themeColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        msg.isTyping ? "GHOST..." : "GHOST",
                        style: TextStyle(
                          fontFamily: 'ShareTechMono',
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  msg.text,
                  style: TextStyle(
                    fontFamily: isGhost ? 'VT323' : 'ShareTechMono',
                    fontSize: isGhost ? 14 : 12,
                    color: isGhost ? Colors.white : Colors.black,
                    height: 1.3,
                  ),
                ),
                if (msg.isTyping)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 20,
                      height: 4,
                      child: LinearProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                        backgroundColor: Colors.transparent,
                        minHeight: 2,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestionChips(List<String> chips, Color themeColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips.map((chip) => ActionChip(
          label: Text(chip, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.black)),
          backgroundColor: themeColor,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          onPressed: () => _handleUserInput(chip),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide.none,
        )).toList(),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isGhost;
  final bool isTyping;
  final List<String>? chips;

  _ChatMessage({
    required this.text,
    required this.isGhost,
    this.isTyping = false,
    this.chips,
  });
}

class _LaunchStep {
  final String text;
  final int pauseAfter;
  final bool isLaugh;

  _LaunchStep({required this.text, required this.pauseAfter, this.isLaugh = false});
}
