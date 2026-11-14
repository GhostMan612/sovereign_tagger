// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/workbench/pending_import_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PendingImportStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sovereign_pending_test_');
    store = PendingImportStore(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('recovery manifest persists outside the cache and survives reopen', () async {
    final source = File('${root.path}/render.wav');
    await source.writeAsString('media bytes');
    final saved = await store.preserve(
      staged: source,
      jobId: 'job_a',
      title: 'Recovered audio',
    );
    expect(saved.available, isTrue);
    expect(saved.filePath, isNot(source.path));
    expect(await File(saved.filePath).exists(), isTrue);
    final reloaded = await PendingImportStore(root).list();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, saved.id);
    expect(reloaded.single.available, isTrue);
    expect(reloaded.single.title, 'Recovered audio');
  });

  test('equal-length corruption blocks recovery until operator discards', () async {
    final source = File('${root.path}/render.mp3');
    await source.writeAsString('abc');
    final saved = await store.preserve(
      staged: source, jobId: 'job_b', title: 'Track',
    );
    await File(saved.filePath).writeAsString('abd');
    final listed = await store.list();
    expect(listed.single.available, isFalse);
    var called = false;
    await expectLater(
      store.retry(listed.single, (path, title) async {
        called = true;
        return 'content://media/audio/1';
      }),
      throwsStateError,
    );
    expect(called, isFalse);
    await store.discard(listed.single);
    expect(await store.list(), isEmpty);
  });

  test('failed import retains manifest and verified media', () async {
    final source = File('${root.path}/render.flac');
    await source.writeAsString('media bytes');
    final saved = await store.preserve(
      staged: source, jobId: 'job_c', title: 'Lossless',
    );
    await expectLater(
      store.retry(saved, (path, title) async => null),
      throwsStateError,
    );
    expect((await store.list()).single.available, isTrue);
  });

  test('verified retry commits URI then removes private staging', () async {
    final source = File('${root.path}/render.m4a');
    await source.writeAsString('media bytes');
    final saved = await store.preserve(
      staged: source, jobId: 'job_d', title: 'Podcast',
    );
    final uri = await store.retry(
      saved,
      (path, title) async {
        expect(title, 'Podcast');
        expect(await File(path).readAsString(), 'media bytes');
        return 'content://media/external/audio/123';
      },
    );
    expect(uri, 'content://media/external/audio/123');
    expect(await store.list(), isEmpty);
    expect(await File(saved.filePath).exists(), isFalse);
  });

  test('manifest path traversal fields are rejected, not imported', () async {
    final pending = Directory('${root.path}/workbench_pending_imports');
    await pending.create(recursive: true);
    await File('${pending.path}/evil.json').writeAsString(
      '{"v":1,"id":"evil","fileName":"../private.wav",'
      '"bytes":3,"sha256":"bad","title":"evil","createdAt":"2026-11-12"}',
    );
    expect(await store.list(), isEmpty);
  });
}
