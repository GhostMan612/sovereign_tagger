// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/storage_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.sovereign.tagger/storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

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

    test('decryptConfig throws ArgumentError on malformed non-JSON data', () async {
      expect(() => StorageClient.decryptConfig('not_a_valid_base64_or_sov2!!'), throwsArgumentError);
    });

    test('encryptConfig invokes native channel with passphrase', () async {
      String? recordedPassphrase;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'encryptConfig') {
            recordedPassphrase = call.arguments['passphrase'];
            return 'SOV2:P:mockSalt:mockIv:mockCipher';
          }
          return null;
        },
      );

      final res = await StorageClient.encryptConfig('{"key":"val"}', passphrase: 'alpha-omega-pass');
      expect(res, 'SOV2:P:mockSalt:mockIv:mockCipher');
      expect(recordedPassphrase, 'alpha-omega-pass');
    });

    test('encryptConfig throws StateError when native channel returns empty or fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => '',
      );

      expect(() => StorageClient.encryptConfig('{"key":"val"}'), throwsStateError);
    });

    test('decryptConfig on SOV2 invokes native channel and forwards passphrase', () async {
      String? passedPassphrase;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'decryptConfig') {
            passedPassphrase = call.arguments['passphrase'];
            return '{"restored":true}';
          }
          return null;
        },
      );

      final decrypted = await StorageClient.decryptConfig(
        'SOV2:P:mockSalt:mockIv:mockCipher',
        passphrase: 'secret-phrase',
      );
      expect(decrypted, '{"restored":true}');
      expect(passedPassphrase, 'secret-phrase');
    });

    test('decryptConfig bubbles authentication failure and refuses silent XOR fallback', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'decryptConfig') {
            throw PlatformException(code: 'STORAGE_ERROR', message: 'AEADBadTagException: Tag mismatch');
          }
          return null;
        },
      );

      expect(
        () => StorageClient.decryptConfig('SOV2:P:tamperedSalt:tamperedIv:tamperedCipher', passphrase: 'wrong'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('decryptConfig forwards parameterized SOV2:P with iterations to native bridge', () async {
      String? recordedPayload;
      String? recordedPassphrase;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'decryptConfig') {
            recordedPayload = call.arguments['data'];
            recordedPassphrase = call.arguments['passphrase'];
            return '{"stretched":true}';
          }
          return null;
        },
      );

      final decrypted = await StorageClient.decryptConfig(
        'SOV2:P:250000:mockSaltB64:mockIvB64:mockCipherB64',
        passphrase: 'high-entropy-pass',
      );
      expect(decrypted, '{"stretched":true}');
      expect(recordedPayload, 'SOV2:P:250000:mockSaltB64:mockIvB64:mockCipherB64');
      expect(recordedPassphrase, 'high-entropy-pass');
    });

    test('decryptConfig supports legacy Phase 38 SOV2 envelope delegation', () async {
      String? recordedPayload;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'decryptConfig') {
            recordedPayload = call.arguments['data'];
            return '{"legacy_phase38":true}';
          }
          return null;
        },
      );

      final decrypted = await StorageClient.decryptConfig('SOV2:saltB64:ivB64:cipherB64');
      expect(decrypted, '{"legacy_phase38":true}');
      expect(recordedPayload, 'SOV2:saltB64:ivB64:cipherB64');
    });

    test('recoverPendingOverwrites parses and casts vault reports', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'recoverPendingOverwrites') {
            return [
              {
                'backupPath': '/data/user/0/sov_recovery/sov_rec_1.bak',
                'backupName': 'sov_rec_1.bak',
                'uri': 'content://media/external/audio/media/100',
                'size': '4096',
                'sha256': 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
                'status': 'RETAINED_FAILED_RESTORE',
              }
            ];
          }
          return null;
        },
      );

      final reports = await StorageClient.recoverPendingOverwrites();
      expect(reports.length, 1);
      expect(reports[0]['backupName'], 'sov_rec_1.bak');
      expect(reports[0]['sha256'], 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890');
      expect(reports[0]['status'], 'RETAINED_FAILED_RESTORE');
    });

    test('restorePendingOverwrite invokes native channel and returns verification outcome', () async {
      String? targetPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'restorePendingOverwrite') {
            targetPath = call.arguments['backupPath'];
            return {
              'status': 'RESTORED',
              'uri': 'content://media/external/audio/media/100',
              'sha256': '1122334455667788990011223344556677889900112233445566778899001122',
              'bytes': '4096',
            };
          }
          return null;
        },
      );

      final res = await StorageClient.restorePendingOverwrite('/data/user/0/sov_recovery/sov_rec_1.bak');
      expect(targetPath, '/data/user/0/sov_recovery/sov_rec_1.bak');
      expect(res['status'], 'RESTORED');
      expect(res['bytes'], '4096');
      expect(res['sha256'], '1122334455667788990011223344556677889900112233445566778899001122');
    });

    test('discardPendingOverwrite invokes native channel and returns true', () async {
      String? discardedPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'discardPendingOverwrite') {
            discardedPath = call.arguments['backupPath'];
            return true;
          }
          return null;
        },
      );

      final ok = await StorageClient.discardPendingOverwrite('/data/user/0/sov_recovery/sov_rec_1.bak');
      expect(ok, isTrue);
      expect(discardedPath, '/data/user/0/sov_recovery/sov_rec_1.bak');
    });

    test('recoverPendingOverwrites preserves COMMITTED_PRE_CLEANUP transaction state', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'recoverPendingOverwrites') {
            return [
              {
                'backupPath': '/data/user/0/sov_recovery/sov_rec_2.bak',
                'backupName': 'sov_rec_2.bak',
                'uri': 'content://media/external/audio/media/200',
                'size': '8192',
                'sha256': '1111222233334444555566667777888811112222333344445555666677778888',
                'status': 'COMMITTED_PRE_CLEANUP',
                'srcSha': 'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
                'destSha': 'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
              }
            ];
          }
          return null;
        },
      );

      final reports = await StorageClient.recoverPendingOverwrites();
      expect(reports.length, 1);
      expect(reports[0]['status'], 'COMMITTED_PRE_CLEANUP');
      expect(reports[0]['srcSha'], reports[0]['destSha']);
    });

    test('recoverPendingOverwrites marks unverified destination as DESTINATION_HASH_UNVERIFIED', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'recoverPendingOverwrites') {
            return [
              {
                'backupPath': '/data/user/0/sov_recovery/sov_rec_3.bak',
                'backupName': 'sov_rec_3.bak',
                'uri': 'content://media/external/audio/media/300',
                'size': '4096',
                'sha256': '1111222233334444555566667777888811112222333344445555666677778888',
                'status': 'DESTINATION_HASH_UNVERIFIED',
                'srcSha': 'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
                'destSha': '',
              }
            ];
          }
          return null;
        },
      );

      final reports = await StorageClient.recoverPendingOverwrites();
      expect(reports.length, 1);
      expect(reports[0]['status'], 'DESTINATION_HASH_UNVERIFIED');
    });

    test('discardPendingOverwrite preserves false on incomplete native deletion', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'discardPendingOverwrite') {
            return false;
          }
          return null;
        },
      );

      final ok = await StorageClient.discardPendingOverwrite('/data/user/0/sov_recovery/sov_rec_1.bak');
      expect(ok, isFalse);
    });

    test('runNativeSecuritySelfTest invokes native channel and receives all passed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'runNativeSecuritySelfTest') {
            return {
              'format_correct': true,
              'roundtrip_passphrase': true,
              'tamper_resistance': true,
              'min_iterations_enforced': true,
              'max_iterations_enforced': true,
              'legacy_phase38_fallback': true,
              'path_traversal_confinement': true,
              'discard_cleanup_success': true,
              'discard_atomic_success': true,
              'all_passed': true,
            };
          }
          return null;
        },
      );

      final results = await StorageClient.runNativeSecuritySelfTest();
      expect(results['all_passed'], isTrue);
      expect(results['path_traversal_confinement'], isTrue);
      expect(results['tamper_resistance'], isTrue);
      expect(results['discard_cleanup_success'], isTrue);
      expect(results['discard_atomic_success'], isTrue);
    });

    test('restorePendingOverwrite bubbles SecurityException on path traversal attempt', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'restorePendingOverwrite') {
            throw PlatformException(code: 'STORAGE_ERROR', message: 'SecurityException: Path traversal rejected');
          }
          return null;
        },
      );

      expect(
        () => StorageClient.restorePendingOverwrite('../../etc/hosts'),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
