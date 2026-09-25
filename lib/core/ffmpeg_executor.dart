// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:collection';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

class FFmpegExecutor {
  static final Queue<_Job> _queue = Queue<_Job>();
  static bool _busy = false;

  static Future<FFmpegSession> execute(
    String command, {
    int? durationMs,
    void Function(double progress)? onProgress,
    void Function(Statistics)? onStatistics,
    String? description,
  }) async {
    final completer = Completer<FFmpegSession>();
    _queue.add(_Job(command, durationMs, onProgress, onStatistics, description, completer));
    unawaited(_drain());
    return completer.future;
  }

  static Future<void> _drain() async {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    final job = _queue.removeFirst();
    try {
      final session = await FFmpegKit.executeAsync(
        job.command,
        onStatistics: job.onStatistics ??
            (job.durationMs != null && job.onProgress != null
                ? (stats) {
                    final d = job.durationMs!;
                    if (d <= 0) return;
                    final p = (stats.time / d).clamp(0.0, 1.0);
                    job.onProgress!(p);
                  }
                : null),
      );
      if (!job.completer.isCompleted) job.completer.complete(session);
    } catch (e) {
      if (!job.completer.isCompleted) job.completer.completeError(e);
    } finally {
      _busy = false;
      if (_queue.isNotEmpty) _drain();
    }
  }

  static Future<String?> probeOutput(FFmpegSession session) async {
    try {
      return session.getOutput();
    } catch (_) {
      return null;
    }
  }
}

class _Job {
  final String command;
  final int? durationMs;
  final void Function(double)? onProgress;
  final void Function(Statistics)? onStatistics;
  final String? description;
  final Completer<FFmpegSession> completer;
  _Job(this.command, this.durationMs, this.onProgress, this.onStatistics, this.description, this.completer);
}
