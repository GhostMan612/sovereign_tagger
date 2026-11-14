// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sovereign.tagger/ytdlp');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpSettingsToUpdater(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.text('CHECK FOR YT-DLP UPDATE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Settings displays overlay status and APK-managed dependency copy without runtime pip trigger', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.11.14',
          'active_source': 'overlay',
          'pending_version': null,
          'restart_required': false,
          'recovery_required': false,
        });
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);

    expect(find.text('BUNDLED YT-DLP: 2026.10.26'), findsOneWidget);
    expect(find.text('ACTIVE YT-DLP: 2026.11.14 (OVERLAY)'), findsOneWidget);
    expect(find.text('CHECK FOR YT-DLP UPDATE'), findsOneWidget);
    expect(find.textContaining('MUTAGEN AND LYRICSGENIUS ARE UPGRADED WITH A NEW APK'), findsOneWidget);
    expect(find.text('FULL STACK REFRESH (YT-DLP + DEPS)'), findsNothing);
  });

  testWidgets('CHECK FOR YT-DLP UPDATE transitions to RESTART REQUIRED when update staged', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
          'restart_required': false,
          'recovery_required': false,
        });
      }
      if (call.method == 'updateCore') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
          'pending_version': '2026.11.14',
          'restart_required': true,
          'recovery_required': false,
          'message': 'yt-dlp 2026.11.14 verified and staged. Restart Sovereign Tagger to activate.',
        });
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);
    await tester.ensureVisible(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.tap(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PENDING OVERLAY: 2026.11.14 — RESTART REQUIRED TO ACTIVATE'), findsOneWidget);
    expect(find.textContaining('Restart Sovereign Tagger to activate'), findsWidgets);
  });

  testWidgets('Settings shows initial pending restart banner from active.json state', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
          'pending_version': '2026.12.01',
          'restart_required': true,
          'recovery_required': false,
        });
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);

    expect(find.text('ACTIVE YT-DLP: 2026.10.26 (BUNDLED)'), findsOneWidget);
    expect(find.text('PENDING OVERLAY: 2026.12.01 — RESTART REQUIRED TO ACTIVATE'), findsOneWidget);
    expect(find.textContaining('RESTART REQUIRED TO ACTIVATE YT-DLP 2026.12.01'), findsOneWidget);
  });

  testWidgets('Settings renders ROLLBACK NOTICE after startup automatic fallback', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
          'restart_required': false,
          'recovery_required': false,
          'rolled_back': true,
          'rolled_back_from': '2026.12.01',
          'last_error': 'Pending overlay failed smoke check',
        });
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);

    expect(find.text('ROLLBACK NOTICE: REVERTED FROM 2026.12.01'), findsOneWidget);
    expect(find.textContaining('ROLLED BACK FROM 2026.12.01'), findsOneWidget);
  });

  testWidgets('CHECK FOR YT-DLP UPDATE surfaces error and RECOVERY REQUIRED states', (tester) async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
        });
      }
      if (call.method == 'updateCore') {
        callCount += 1;
        if (callCount == 1) {
          return jsonEncode(<String, dynamic>{
            'status': 'error',
            'recovery_required': false,
            'message': 'Archive SHA-256 verification failed',
          });
        }
        return jsonEncode(<String, dynamic>{
          'status': 'error',
          'recovery_required': true,
          'message': 'Disk write fault during manifest commit',
        });
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);
    await tester.ensureVisible(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.tap(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('ERR: Update Failed: Archive SHA-256 verification failed'), findsOneWidget);

    await tester.tap(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('STATE: RECOVERY REQUIRED'), findsOneWidget);
    expect(find.textContaining('RECOVERY REQUIRED: Disk write fault'), findsOneWidget);
  });

  testWidgets('CHECK FOR YT-DLP UPDATE handles disposal safely while pending', (tester) async {
    final completer = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUpdaterStatus') {
        return jsonEncode(<String, dynamic>{
          'status': 'success',
          'bundled_version': '2026.10.26',
          'active_version': '2026.10.26',
          'active_source': 'bundled',
        });
      }
      if (call.method == 'updateCore') {
        return completer.future;
      }
      return null;
    });

    await pumpSettingsToUpdater(tester);
    await tester.ensureVisible(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.tap(find.text('CHECK FOR YT-DLP UPDATE'));
    await tester.pump();
    expect(find.text('UPDATING CORE ENGINE...'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completer.complete(jsonEncode(<String, dynamic>{'status': 'success', 'message': 'late'}));
    await tester.pump();
  });
}
