// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/core/feedback_settings.dart';
import 'package:sovereign_tagger/core/model_lifecycle.dart';
import 'package:sovereign_tagger/screens/settings_screen.dart';

class _UpdaterSettingsHarness {
  static const updater = MethodChannel('com.sovereign.tagger/ytdlp');
  static const storage = MethodChannel('com.sovereign.tagger/storage');
  static const secrets = MethodChannel('com.sovereign.tagger/secrets');
  static const paths = MethodChannel('plugins.flutter.io/path_provider');
  static const embeddings = MethodChannel('com.sovereign.tagger/embeddings');
  static const sfx = MethodChannel('com.sovereign.tagger/sfx');

  final calls = <MethodCall>[];
  final secretReads = <String>[];
  final storageCalls = <String>[];
  final queued = <Completer<String>>[];
  final allResponses = <Completer<String>>[];
  final bool oldBackdrop = FeedbackSettings.backdrop.value;
  final bool oldSound = FeedbackSettings.sound.value;
  final bool oldHaptics = FeedbackSettings.haptics.value;
  late final Directory fixtureBase;
  late final Directory fixture;
  var activeRequests = 0;

  Completer<String> queueResponse() {
    final response = Completer<String>();
    queued.add(response);
    allResponses.add(response);
    return response;
  }

  void install() {
    fixtureBase = Directory('${Directory.current.path}/build/pr87_settings_tests')
      ..createSync(recursive: true);
    fixture = fixtureBase.createTempSync('case_');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FeedbackSettings.backdrop.value = false;
    FeedbackSettings.sound.value = false;
    FeedbackSettings.haptics.value = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (call) async {
      if (call.method.startsWith('get')) return fixture.path;
      throw StateError('Unexpected path method ${call.method}');
    });
    messenger.setMockMethodCallHandler(secrets, (call) async {
      if (call.method != 'get') throw StateError('Credential mutation is forbidden in this fixture');
      secretReads.add((call.arguments as Map<Object?, Object?>)['name'] as String);
      return null;
    });
    messenger.setMockMethodCallHandler(storage, (call) async {
      storageCalls.add(call.method);
      return switch (call.method) {
        'recoverPendingOverwrites' => <Object?>[],
        'getTempDirectory' => fixture.path,
        'sdkInt' => 36,
        'getBuildProvenance' => <String, Object>{
          'sourceSha': '0000000000000000000000000000000000000000',
          'sourceDirty': false,
          'versionCode': 1,
          'versionName': 'fixture',
          'buildAbis': 'fixture',
          'builtAtUtc': '2026-11-14T00:00:00Z',
        },
        _ => throw StateError('Unexpected storage method ${call.method}'),
      };
    });
    messenger.setMockMethodCallHandler(embeddings, (call) async {
      if (call.method == 'status') {
        return <String, Object>{
          'loaded': false,
          'filesReady': false,
          'availRamMb': 4096,
          'totalRamMb': 6144,
          'lowMemory': false,
        };
      }
      if (call.method == 'isAvailable') return false;
      throw StateError('Unexpected embedding method ${call.method}');
    });
    messenger.setMockMethodCallHandler(sfx, (_) async => true);
    messenger.setMockMethodCallHandler(updater, (call) async {
      if (call.method != 'updateCore' && call.method != 'updateFullStack') {
        throw StateError('Unexpected updater method ${call.method}');
      }
      calls.add(call);
      if (queued.isEmpty) throw StateError('No controlled updater response queued');
      final response = queued.removeAt(0);
      activeRequests++;
      try {
        return await response.future;
      } finally {
        activeRequests--;
      }
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    for (final response in allResponses) {
      if (!response.isCompleted) {
        response.complete(jsonEncode({'status': 'error', 'message': 'fixture cleanup'}));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _until(tester, () => activeRequests == 0);
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [updater, storage, secrets, paths, embeddings, sfx]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    FeedbackSettings.backdrop.value = oldBackdrop;
    FeedbackSettings.sound.value = oldSound;
    FeedbackSettings.haptics.value = oldHaptics;
    final base = fixtureBase.resolveSymbolicLinksSync();
    final path = fixture.resolveSymbolicLinksSync();
    if (!path.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Fixture escaped its workspace directory');
    }
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'Controlled updater checkpoint was not reached');
  await tester.pump();
}

Finder _button(String method, {bool pending = false}) => find.widgetWithText(
  OutlinedButton,
  method == 'updateCore'
      ? (pending ? 'UPDATING CORE ENGINE...' : 'CHECK FOR YT-DLP UPDATE')
      : 'FULL STACK REFRESH (YT-DLP + DEPS)',
);

bool _enabled(WidgetTester tester, String method, {bool pending = false}) =>
    tester.widget<OutlinedButton>(_button(method, pending: pending)).onPressed != null;

Future<void> _open(WidgetTester tester, _UpdaterSettingsHarness harness) async {
  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await _until(tester, () => harness.secretReads.contains('hf_token')
      && harness.storageCalls.contains('recoverPendingOverwrites')
      && harness.storageCalls.contains('getBuildProvenance')
      && ModelLifecycle.instance.state.value.statusText.startsWith('FALLBACK'));
}

Future<void> _tapUpdate(WidgetTester tester, String method) async {
  await tester.ensureVisible(_button(method));
  await tester.tap(_button(method));
  await tester.pump();
}

Map<String, Object?> _recoveryRequired(String method) {
  final core = <String, Object?>{
    'status': 'error',
    'message': 'fixture rollback blocked',
    'recovery_required': true,
  };
  return method == 'updateCore' ? core : <String, Object?>{
    ...core,
    'core': core,
    'python_stack': null,
  };
}

Map<String, Object?> _success(String method) {
  final core = <String, Object?>{'status': 'success', 'message': 'fixture core committed'};
  return method == 'updateCore' ? core : <String, Object?>{
    'status': 'success',
    'core': core,
    'python_stack': <String, Object>{'status': 'success'},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final method in ['updateCore', 'updateFullStack']) {
    testWidgets('$method reports recovery required, disables pending controls and permits retry', (tester) async {
      final harness = _UpdaterSettingsHarness()..install();
      try {
        await _open(tester, harness);
        final failed = harness.queueResponse();
        await _tapUpdate(tester, method);
        await _until(tester, () => harness.calls.length == 1);
        expect(harness.calls.single.method, method);
        expect(harness.calls.single.arguments, isNull);
        expect(_enabled(tester, 'updateCore', pending: true), isFalse);
        expect(_enabled(tester, 'updateFullStack'), isFalse);
        expect(find.textContaining('RECOVERY REQUIRED:'), findsNothing);

        failed.complete(jsonEncode(_recoveryRequired(method)));
        await _until(tester, () => find.textContaining('RECOVERY REQUIRED: fixture rollback blocked').evaluate().isNotEmpty);
        expect(find.textContaining('Backup retained; retry after resolving the storage fault.'), findsOneWidget);
        expect(_enabled(tester, 'updateCore'), isTrue);
        expect(_enabled(tester, 'updateFullStack'), isTrue);

        final retry = harness.queueResponse();
        await _tapUpdate(tester, method);
        await _until(tester, () => harness.calls.length == 2);
        expect(harness.calls.last.method, method);
        retry.complete(jsonEncode(_success(method)));
        await _until(tester, () => find.textContaining('fixture core committed').evaluate().isNotEmpty);
        expect(find.textContaining('RECOVERY REQUIRED:'), findsNothing);
        expect(find.text('> null'), findsNothing);
        expect(_enabled(tester, 'updateCore'), isTrue);
        expect(_enabled(tester, 'updateFullStack'), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });

    testWidgets('$method reports ordinary update error without claiming recovery evidence', (tester) async {
      final harness = _UpdaterSettingsHarness()..install();
      try {
        await _open(tester, harness);
        final response = harness.queueResponse();
        await _tapUpdate(tester, method);
        await _until(tester, () => harness.calls.length == 1);
        response.complete(jsonEncode({'status': 'error', 'message': 'fixture download rejected'}));
        await _until(tester, () => find.textContaining('fixture download rejected').evaluate().isNotEmpty);
        expect(find.textContaining(method == 'updateCore' ? 'ERR: Update Failed:' : 'ERR: Full Stack Failed:'), findsOneWidget);
        expect(find.textContaining('RECOVERY REQUIRED:'), findsNothing);
        expect(_enabled(tester, 'updateCore'), isTrue);
        expect(_enabled(tester, 'updateFullStack'), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });

    testWidgets('$method pending completion after disposal does not update UI', (tester) async {
      final harness = _UpdaterSettingsHarness()..install();
      try {
        await _open(tester, harness);
        final response = harness.queueResponse();
        await _tapUpdate(tester, method);
        await _until(tester, () => harness.calls.length == 1);
        await tester.pumpWidget(const SizedBox.shrink());
        response.complete(jsonEncode(_recoveryRequired(method)));
        await _until(tester, () => harness.activeRequests == 0);
        expect(find.byType(SettingsScreen), findsNothing);
        expect(find.textContaining('RECOVERY REQUIRED:'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('full stack partial response retains the helper-package failure detail', (tester) async {
    final harness = _UpdaterSettingsHarness()..install();
    try {
      await _open(tester, harness);
      final response = harness.queueResponse();
      await _tapUpdate(tester, 'updateFullStack');
      await _until(tester, () => harness.calls.length == 1);
      response.complete(jsonEncode({
        'status': 'partial',
        'core': {'status': 'success', 'message': 'fixture core committed'},
        'python_stack': {'status': 'error', 'message': 'fixture helper rollback attempted'},
      }));
      await _until(tester, () => find.textContaining('PARTIAL: yt-dlp updated; fixture helper rollback attempted').evaluate().isNotEmpty);
      expect(find.textContaining('RECOVERY REQUIRED:'), findsNothing);
      expect(_enabled(tester, 'updateCore'), isTrue);
      expect(_enabled(tester, 'updateFullStack'), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
