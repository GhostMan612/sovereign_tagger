// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ModelDigest {
  const ModelDigest._();

  static Future<bool> matches(
    File file, {
    required int bytes,
    required String sha256Hex,
  }) async {
    if (!await file.exists() || await file.length() != bytes) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == sha256Hex.toLowerCase();
  }

  static Future<void> installBytes(
    File destination,
    Uint8List bytes, {
    required int expectedBytes,
    required String sha256Hex,
  }) async {
    if (bytes.lengthInBytes != expectedBytes ||
        sha256.convert(bytes).toString() != sha256Hex.toLowerCase()) {
      throw const FileSystemException('Bundled model identity verification failed');
    }
    final staging = File('${destination.path}.part');
    try {
      await staging.writeAsBytes(bytes, flush: true);
      await installVerifiedPart(
        destination,
        staging,
        expectedBytes: expectedBytes,
        sha256Hex: sha256Hex,
      );
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  static Future<void> installVerifiedPart(
    File destination,
    File staging, {
    required int expectedBytes,
    required String sha256Hex,
  }) async {
    if (!await matches(
      staging,
      bytes: expectedBytes,
      sha256Hex: sha256Hex,
    )) {
      throw const FileSystemException('Staged model failed SHA-256 identity verification');
    }
    await staging.rename(destination.path);
  }
}
