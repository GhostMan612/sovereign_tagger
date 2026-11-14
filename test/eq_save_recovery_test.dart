// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/core/eq_mapper.dart';
import 'package:sovereign_tagger/core/playback_fx.dart';
import 'package:sovereign_tagger/screens/eq_presets_screen.dart';

class _Gate {
  final started = Completer<void>();
  final result = Completer<bool>();
}

class _EqHarness {
  static const native = MethodChannel('com.sovereign.tagger/audio_fx');
  static const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  final values = <String, Object>{
    for (var i = 0; i < 15; i++) 'flutter.eq15_band_$i': 0.0,
  };
  final nativeCalls = <List<double>>[];
  final nativeGates = <_Gate>[];
  final allGates = <_Gate>[];
  List<double> nativeGains = List<double>.filled(15, 0.0);
  int activeNative = 0;
  int maxActiveNative = 0;
  int completedWrites = 0;
  String? failKey;
  bool throwWrite = false;
  String? heldWriteKey;
  _Gate? writeGate;

  List<double?> get persisted => List<double?>.generate(
    15, (i) => values['flutter.eq15_band_$i'] as double?,
  );

  _Gate blockNative() {
    final gate = _Gate();
    nativeGates.add(gate);
    allGates.add(gate);
    return gate;
  }

  _Gate blockWrite(int band) {
    final gate = _Gate();
    heldWriteKey = 'flutter.eq15_band_$band';
    writeGate = gate;
    allGates.add(gate);
    return gate;
  }

  Future<void> install() async {
    SharedPreferences.resetStatic();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.from(values);
      final args = call.arguments as Map<Object?, Object?>;
      final key = args['key'] as String;
      if (call.method == 'remove') {
        values.remove(key);
        return true;
      }
      if (call.method == 'setDouble') {
        if (key == failKey) {
          failKey = null;
          if (throwWrite) throw PlatformException(code: 'TEST_WRITE_FAILED');
          return false;
        }
        if (key == heldWriteKey) {
          heldWriteKey = null;
          final gate = writeGate!;
          gate.started.complete();
          if (!await gate.result.future) return false;
        }
        values[key] = args['value'] as double;
        completedWrites++;
        return true;
      }
      throw StateError('Unexpected preferences method ${call.method}');
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'attachSession') {
        return {'engine': 'dynamics15', 'bands': EqMapper.bandFrequencies};
      }
      if (call.method == 'applyLoudness') return true;
      if (call.method != 'applyEq') return null;
      final args = call.arguments as Map<Object?, Object?>;
      final gains = (args['gainsDb'] as List<Object?>)
          .map((value) => (value as num).toDouble()).toList();
      nativeCalls.add(gains);
      activeNative++;
      if (activeNative > maxActiveNative) maxActiveNative = activeNative;
      try {
        final gate = nativeGates.isEmpty ? null : nativeGates.removeAt(0);
        if (gate != null) gate.started.complete();
        final applied = gate == null ? true : await gate.result.future;
        if (applied) nativeGains = gains;
        return applied;
      } finally {
        activeNative--;
      }
    });
    PlaybackFx.eqGains.value = List<double>.filled(15, 0.0);
    PlaybackFx.eqEnabled.value = true;
    await PlaybackFx.attachSession(42);
    nativeCalls.clear();
  }

  Future<void> dispose(WidgetTester tester) async {
    nativeGates.clear();
    heldWriteKey = null;
    for (final gate in allGates) {
      if (!gate.result.isCompleted) gate.result.complete(true);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 50; i++) {
      await tester.pump();
    }
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(preferences, null);
    SharedPreferences.resetStatic();
    PlaybackFx.eqGains.value = List<double>.filled(15, 0.0);
  }
}

Future<void> _until(WidgetTester tester, bool Function() done, {Duration frame = Duration.zero}) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump(frame);
  }
  expect(done(), isTrue, reason: 'Expected asynchronous checkpoint was not reached');
  await tester.pump();
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
      body: ElevatedButton(
        onPressed: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const EqPresetsScreen())),
        child: const Text('OPEN_EQ'),
      ),
    )),
  ));
  await tester.tap(find.text('OPEN_EQ'));
  await tester.pump();
  await _until(tester, () => find.byType(EqPresetsScreen).evaluate().isNotEmpty,
    frame: const Duration(milliseconds: 16));
  final route = ModalRoute.of(tester.element(find.byType(EqPresetsScreen)))!;
  await _until(tester, () => route.animation!.status == AnimationStatus.completed,
    frame: const Duration(milliseconds: 16));
}

void _change(WidgetTester tester, double value) {
  tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(value);
}

List<double> _curve(double value) => List<double>.filled(15, 0.0)..[0] = value;

bool _canSave(WidgetTester tester) => tester.widget<OutlinedButton>(
  find.widgetWithText(OutlinedButton, 'SAVE PRESET'),
).onPressed != null;

bool _canPop(WidgetTester tester) => tester.widget<PopScope>(
  find.descendant(of: find.byType(EqPresetsScreen), matching: find.byWidgetPredicate((widget) => widget is PopScope)),
).canPop;

Finder _status(String text) => find.descendant(
  of: find.byType(EqPresetsScreen), matching: find.textContaining(text),
);

Future<void> _finishDiscard(WidgetTester tester) async {
  final route = ModalRoute.of(tester.element(find.byType(EqPresetsScreen)))!;
  var popped = false;
  var completed = false;
  route.popped.then((_) => popped = true);
  route.completed.then((_) => completed = true);
  await _until(tester, () => popped);
  await _until(tester, () => completed, frame: const Duration(milliseconds: 16));
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('SAVE PRESET'));
  await tester.tap(find.text('SAVE PRESET'));
  await tester.pump();
}

Future<void> _discard(WidgetTester tester) async {
  await tester.ensureVisible(find.byIcon(Icons.arrow_back));
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.text('UNSAVED PRESET'), findsOneWidget);
  await tester.tap(find.text('DISCARD'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending second Save blocks Back even when current gains match first Save', (tester) async {
    final harness = _EqHarness();
    await harness.install();
    try {
      await _open(tester);
      _change(tester, 9.0);
      await _until(tester, () => harness.activeNative == 0 && harness.nativeCalls.isNotEmpty);
      final firstSave = harness.blockNative();
      await _save(tester);
      await _until(tester, () => firstSave.started.isCompleted);
      _change(tester, 11.0);
      await tester.pump();
      await _save(tester);
      _change(tester, 9.0);
      final secondSave = harness.blockNative();
      firstSave.result.complete(true);
      await _until(tester, () => secondSave.started.isCompleted);
      expect(harness.persisted, _curve(9.0));
      expect(_canPop(tester), isFalse);
      await _discard(tester);
      expect(find.byType(EqPresetsScreen), findsOneWidget);
      secondSave.result.complete(true);
      await _until(tester, () => harness.completedWrites == 30 && harness.activeNative == 0);
      await _finishDiscard(tester);
      expect(find.byType(EqPresetsScreen), findsNothing);
      expect(harness.persisted, _curve(11.0));
      expect(harness.nativeGains, _curve(11.0));
      expect(harness.maxActiveNative, 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('Discard waits for queued Save and restores its committed snapshot', (tester) async {
    final harness = _EqHarness();
    await harness.install();
    try {
      await _open(tester);
      final drag = harness.blockNative();
      _change(tester, 4.0);
      await _until(tester, () => drag.started.isCompleted);
      _change(tester, 9.0);
      await tester.pump();
      await _save(tester);
      _change(tester, 11.0);
      await tester.pump();
      await _discard(tester);
      expect(find.byType(EqPresetsScreen), findsOneWidget);
      expect(harness.persisted, _curve(0.0));
      drag.result.complete(true);
      await _until(tester, () => harness.completedWrites == 15 && harness.activeNative == 0);
      await _finishDiscard(tester);
      expect(find.byType(EqPresetsScreen), findsNothing);
      expect(harness.persisted, _curve(9.0));
      expect(harness.nativeGains, _curve(9.0));
      expect(harness.maxActiveNative, 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final throwsWrite in [false, true]) {
    testWidgets('preference ${throwsWrite ? 'exception' : 'rejection'} keeps Save dirty and retry recovers', (tester) async {
      final harness = _EqHarness();
      await harness.install();
      try {
        await _open(tester);
        _change(tester, 9.0);
        await _until(tester, () => harness.activeNative == 0 && harness.nativeCalls.isNotEmpty);
        harness.failKey = 'flutter.eq15_band_7';
        harness.throwWrite = throwsWrite;
        await _save(tester);
        await _until(tester, () => find.textContaining('PRESET SAVE FAILED').evaluate().isNotEmpty);
        expect(find.textContaining('PRESET SAVED'), findsNothing);
        expect(_canSave(tester), isTrue);
        expect(_canPop(tester), isFalse);
        expect(harness.persisted, _curve(0.0));
        final prefs = await SharedPreferences.getInstance();
        expect(List<double?>.generate(15, (i) => prefs.getDouble('eq15_band_$i')), _curve(0.0));
        expect(harness.nativeGains, _curve(9.0));
        await _save(tester);
        await _until(tester, () => !_canSave(tester));
        expect(harness.persisted, _curve(9.0));
        expect(_canPop(tester), isTrue);
        _change(tester, -4.0);
        await tester.pump();
        await _discard(tester);
        await _finishDiscard(tester);
        expect(harness.nativeGains, _curve(9.0));
        expect(harness.persisted, _curve(9.0));
        expect(find.byType(EqPresetsScreen), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('Save success waits for the final preference write acknowledgement', (tester) async {
    final harness = _EqHarness();
    await harness.install();
    try {
      await _open(tester);
      _change(tester, 9.0);
      await _until(tester, () => harness.activeNative == 0 && harness.nativeCalls.isNotEmpty);
      final write = harness.blockWrite(14);
      await _save(tester);
      await _until(tester, () => write.started.isCompleted);
      expect(harness.completedWrites, 14);
      expect(find.textContaining('PRESET SAVED'), findsNothing);
      expect(_canPop(tester), isFalse);
      write.result.complete(true);
      await _until(tester, () => !_canSave(tester));
      expect(harness.completedWrites, 15);
      expect(harness.persisted, _curve(9.0));
      expect(_status('PRESET SAVED'), findsOneWidget);
      expect(_canPop(tester), isTrue);
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final failAfterDispose in [false, true]) {
    testWidgets('Save ${failAfterDispose ? 'failure' : 'completion'} after disposal does not touch UI', (tester) async {
      final harness = _EqHarness();
      await harness.install();
      try {
        await _open(tester);
        _change(tester, 9.0);
        await _until(tester, () => harness.activeNative == 0 && harness.nativeCalls.isNotEmpty);
        final save = harness.blockNative();
        await _save(tester);
        await _until(tester, () => save.started.isCompleted);
        if (failAfterDispose) harness.failKey = 'flutter.eq15_band_7';
        await tester.pumpWidget(const SizedBox.shrink());
        save.result.complete(true);
        await _until(tester, () => harness.completedWrites == (failAfterDispose ? 22 : 15));
        expect(harness.persisted, _curve(failAfterDispose ? 0.0 : 9.0));
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('native application failure is distinct from confirmed preset persistence', (tester) async {
    final harness = _EqHarness();
    await harness.install();
    try {
      await _open(tester);
      _change(tester, 9.0);
      await _until(tester, () => harness.activeNative == 0 && harness.nativeCalls.isNotEmpty);
      final save = harness.blockNative();
      await _save(tester);
      await _until(tester, () => save.started.isCompleted);
      save.result.complete(false);
      await _until(tester, () => !_canSave(tester));
      expect(harness.persisted, _curve(9.0));
      expect(PlaybackFx.eqBackend.value, 'error');
      expect(_status('PRESET SAVED. LIVE EQ UPDATE FAILED OR UNAVAILABLE.'), findsOneWidget);
      expect(find.textContaining('PRESET SAVE FAILED'), findsNothing);
      expect(_canPop(tester), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
