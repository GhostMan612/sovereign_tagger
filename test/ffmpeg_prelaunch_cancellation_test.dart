// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/ffmpeg_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scoped cancellation during async pre-execute hook prevents session creation', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    FFmpegExecutor.beforeExecuteHook = () async {
      started.complete();
      await release.future;
    };
    try {
      final work = FFmpegExecutor.execute(
        '-version',
        description: 'workbench_prelaunch_regression',
      );
      final assertion = expectLater(work, throwsA(isA<StateError>()));
      await started.future;
      FFmpegExecutor.cancelCurrent(description: 'workbench_prelaunch_regression');
      release.complete();
      await assertion;
      expect(FFmpegExecutor.isBusy, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      FFmpegExecutor.beforeExecuteHook = null;
    }
  });
}
