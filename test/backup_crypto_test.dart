// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/storage_client.dart';

void main() {
  group('Backup format & cryptographic fallback tests', () {
    test('legacy XOR 0x53 roundtrip encodes and decodes accurately', () {
      const payload = '{"genius_key":"test_key","acr_key":"secret123"}';
      final bytes = utf8.encode(payload);
      final xorBytes = bytes.map((b) => b ^ 0x53).toList();
      final encoded = base64Encode(xorBytes);

      final decoded = base64Decode(encoded);
      final restoredBytes = decoded.map((b) => b ^ 0x53).toList();
      final restored = utf8.decode(restoredBytes);

      expect(restored, payload);
    });

    test('decryptConfig fallback successfully restores legacy XOR payloads', () async {
      const payload = '{"accent_color":4294901820,"gapless":true}';
      final bytes = utf8.encode(payload);
      final xorBytes = bytes.map((b) => b ^ 0x53).toList();
      final legacyB64 = base64Encode(xorBytes);

      final decrypted = await StorageClient.decryptConfig(legacyB64);
      expect(decrypted, payload);
    });

    test('decryptConfig returns empty string on malformed data', () async {
      final decrypted = await StorageClient.decryptConfig('not_a_valid_base64_or_sov2!!');
      expect(decrypted, isEmpty);
    });
  });
}
