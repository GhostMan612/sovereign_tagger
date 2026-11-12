// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/cloud_download.dart';
import 'package:sovereign_tagger/core/cloud_source.dart';

CloudEntry folder(String id) => CloudEntry(
  id: id,
  parentFolderId: '',
  name: id,
  path: '',
  isFolder: true,
);

CloudEntry song(String id) => CloudEntry(
  id: id,
  parentFolderId: '',
  name: '$id.mp3',
  path: '',
  isFolder: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal scan traverses folders and deduplicates repeated media', () async {
    final data = <String, List<CloudEntry>>{
      'root': [song('one'), folder('sub'), song('one')],
      'sub': [song('two')],
    };
    final result = await CloudDownload.scanFolder(
      folder('root'),
      listEntries: (id) async => data[id] ?? const [],
    );
    expect(result.audio.map((entry) => entry.id).toList(), ['one', 'two']);
    expect(result.truncated, isFalse);
    expect(result.cancelled, isFalse);
  });

  test('depth-limit truncation is explicit', () async {
    final data = <String, List<CloudEntry>>{
      'root': [folder('one')],
      'one': [folder('two')],
      'two': [song('deep')],
    };
    final result = await CloudDownload.scanFolder(
      folder('root'),
      maxDepth: 1,
      listEntries: (id) async => data[id] ?? const [],
    );
    expect(result.truncated, isTrue);
    expect(result.truncationReason, contains('depth'));
  });

  test('500-file cap reports partial rather than claiming complete', () async {
    final children = List<CloudEntry>.generate(501, (index) => song('song$index'));
    final result = await CloudDownload.scanFolder(
      folder('root'),
      listEntries: (id) async => children,
    );
    expect(result.audio.length, 500);
    expect(result.truncated, isTrue);
    expect(result.truncationReason, contains('500'));
  });

  test('cancellation stops listing before any network call', () async {
    var calls = 0;
    final result = await CloudDownload.scanFolder(
      folder('root'),
      isCancelled: () => true,
      listEntries: (id) async {
        calls++;
        return [song('one')];
      },
    );
    expect(result.cancelled, isTrue);
    expect(calls, 0);
  });

  test('cycle in folder graph does not rescan or loop', () async {
    var calls = 0;
    final result = await CloudDownload.scanFolder(
      folder('root'),
      listEntries: (id) async {
        calls++;
        return [folder('root'), song('ok')];
      },
    );
    expect(calls, 1);
    expect(result.audio.length, 1);
    expect(result.truncated, isFalse);
  });
}
