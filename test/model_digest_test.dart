// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/model_digest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const abcSha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  test('verified model digest rejects corrupt same-size artifact', () async {
    final folder = await Directory.systemTemp.createTemp('model_identity_');
    try {
      final model = File('${folder.path}/test.bin');
      await model.writeAsString('abc');
      expect(await ModelDigest.matches(model, bytes: 3, sha256Hex: abcSha), isTrue);
      await model.writeAsString('abd');
      expect(await ModelDigest.matches(model, bytes: 3, sha256Hex: abcSha), isFalse);
      expect(await ModelDigest.matches(model, bytes: 4, sha256Hex: abcSha), isFalse);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('staged corruption never replaces the last good model', () async {
    final folder = await Directory.systemTemp.createTemp('model_staging_');
    try {
      final model = File('${folder.path}/test.bin');
      final staging = File('${model.path}.part');
      await model.writeAsString('abc');
      await staging.writeAsString('abd');
      await expectLater(
        ModelDigest.installVerifiedPart(
          model, staging, expectedBytes: 3, sha256Hex: abcSha,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await model.readAsString(), 'abc');
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('bundle install verifies SHA and performs staged replacement', () async {
    final folder = await Directory.systemTemp.createTemp('model_bundle_');
    try {
      final model = File('${folder.path}/test.bin');
      await ModelDigest.installBytes(
        model, utf8.encode('abc'),
        expectedBytes: 3, sha256Hex: abcSha,
      );
      expect(await model.readAsString(), 'abc');
      expect(await File('${model.path}.part').exists(), isFalse);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('invalid bundle never overwrites current verified payload', () async {
    final folder = await Directory.systemTemp.createTemp('model_bad_bundle_');
    try {
      final model = File('${folder.path}/test.bin');
      await model.writeAsString('abc');
      await expectLater(
        ModelDigest.installBytes(
          model, utf8.encode('abd'),
          expectedBytes: 3, sha256Hex: abcSha,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await model.readAsString(), 'abc');
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
