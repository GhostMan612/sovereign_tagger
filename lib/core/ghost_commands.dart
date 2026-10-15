// ============================================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';

enum GrabberMediaMode { m4a, mp3, original, video }

class GrabberSearchHit {
  final String title;
  final String artistOrChannel;
  final String url;
  final int durationSeconds;
  final String source;

  const GrabberSearchHit({
    required this.title,
    required this.artistOrChannel,
    required this.url,
    this.durationSeconds = 0,
    this.source = 'youtube',
  });
}

class GrabberCommand {
  final String queryOrUrl;
  final bool isSearchQuery;
  final String source; // 'youtube' or 'soundcloud'
  final GrabberMediaMode mode;
  final bool autoDownloadTopResult;
  final bool sendToForgeWhenDone;
  final Completer<String>? onResult;

  const GrabberCommand({
    required this.queryOrUrl,
    this.isSearchQuery = true,
    this.source = 'youtube',
    this.mode = GrabberMediaMode.m4a,
    this.autoDownloadTopResult = false,
    this.sendToForgeWhenDone = false,
    this.onResult,
  });
}

enum WorkbenchTaskType {
  transcribeLyricsWhisper,
  analyzeReplayGain,
  openEq,
}

class WorkbenchCommand {
  final String? filePath;
  final WorkbenchTaskType task;
  final Completer<String>? onResult;

  const WorkbenchCommand({
    this.filePath,
    required this.task,
    this.onResult,
  });
}

/// Global reactive command bus for cross-tab GhostBrain v2 automation.
/// Works alongside SovereignState without breaking existing ValueNotifiers.
class GhostCommandBus {
  static final ValueNotifier<GrabberCommand?> pendingGrabberCommand =
      ValueNotifier<GrabberCommand?>(null);

  static final ValueNotifier<WorkbenchCommand?> pendingWorkbenchCommand =
      ValueNotifier<WorkbenchCommand?>(null);

  static String? lastMountedForgePath;
  static String? lastGrabbedUrl;
}
