// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/cloud_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.sovereign.tagger/storage');
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('sovereign_cloud_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTempDirectory') return root.path;
      return null;
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('failed cache replacement preserves the previous offline copy', () async {
    final original = File('${root.path}/source.mp3');
    await original.writeAsString('valid offline audio');
    final cached = await CloudCache.put('42', 'recording.mp3', original);
    expect(await cached.readAsString(), 'valid offline audio');

    final missing = File('${root.path}/missing.mp3');
    await expectLater(
      CloudCache.put('42', 'recording.mp3', missing),
      throwsA(isA<FileSystemException>()),
    );

    expect(await cached.readAsString(), 'valid offline audio');
    final cacheDir = cached.parent;
    final abandoned = cacheDir.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.part'),
    );
    expect(abandoned, isEmpty);
  });

  test('successful replacement updates the offline copy', () async {
    final replacement = File('${root.path}/replacement.mp3');
    await replacement.writeAsString('new audio bytes');
    final cached = await CloudCache.put('42', 'recording.mp3', replacement);
    expect(await cached.readAsString(), 'new audio bytes');
    expect(await CloudCache.get('42', 'recording.mp3'), isNotNull);
  });
}
