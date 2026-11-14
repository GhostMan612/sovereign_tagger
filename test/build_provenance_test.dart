// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/build_provenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sovereign.tagger/storage');

  void mockProvenance(Object? response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => response);
  }

  test('identity line carries every auditable field', () {
    final provenance = BuildProvenance(
      sourceSha: 'a' * 40,
      sourceDirty: false,
      versionCode: 7,
      versionName: '1.0.0',
      buildAbis: 'arm64-v8a,x86_64',
      builtAtUtc: '2026-11-12T00:00:00Z',
    );
    expect(provenance.isComplete, isTrue);
    expect(provenance.identityLine, contains('sha=${'a' * 40}'));
    expect(provenance.identityLine, contains('version=1.0.0(7)'));
    expect(provenance.identityLine, contains('abis=arm64-v8a,x86_64'));
    expect(provenance.identityLine, contains('built=2026-11-12T00:00:00Z'));
    expect(provenance.identityLine, isNot(contains('dirty')));
  });

  test('a dirty source tree is surfaced, not hidden', () {
    final provenance = BuildProvenance(
      sourceSha: 'b' * 40,
      sourceDirty: true,
      versionCode: 1,
      versionName: '1.0.0',
      buildAbis: 'arm64-v8a,x86_64',
      builtAtUtc: '',
    );
    expect(provenance.identityLine, contains('(dirty tree)'));
  });

  test('a short or missing identity is not complete', () {
    const provenance = BuildProvenance(
      sourceSha: 'abc',
      sourceDirty: false,
      versionCode: 0,
      versionName: '',
      buildAbis: '',
      builtAtUtc: '',
    );
    expect(provenance.isComplete, isFalse);
  });

  test('load parses the platform response', () async {
    mockProvenance(<String, dynamic>{
      'sourceSha': 'c' * 40,
      'sourceDirty': false,
      'versionCode': 42,
      'versionName': '1.2.3',
      'buildAbis': 'arm64-v8a,x86_64',
      'builtAtUtc': '2026-11-12T00:00:00Z',
    });
    final provenance = await BuildProvenance.load();
    expect(provenance, isNotNull);
    expect(provenance!.sourceSha, 'c' * 40);
    expect(provenance.sourceDirty, isFalse);
    expect(provenance.versionCode, 42);
    expect(provenance.versionName, '1.2.3');
    expect(provenance.buildAbis, 'arm64-v8a,x86_64');
    expect(provenance.isComplete, isTrue);
  });

  test('load degrades to null when the channel is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    expect(await BuildProvenance.load(), isNull);
  });

  test('load degrades to null on a platform error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'STORAGE_ERROR');
    });
    expect(await BuildProvenance.load(), isNull);
  });

  test('load refuses an empty sha rather than reporting a fake identity',
      () async {
    mockProvenance(<String, dynamic>{'sourceSha': '', 'versionName': '1.0.0'});
    expect(await BuildProvenance.load(), isNull);
  });
}
