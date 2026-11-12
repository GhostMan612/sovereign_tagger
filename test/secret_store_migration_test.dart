// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/core/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final encrypted = <String, String>{};
  bool denyWrite = false;

  setUp(() {
    encrypted.clear();
    denyWrite = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    messenger.setMockMethodCallHandler(SecretStore.channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final name = args['name'] as String;
      switch (call.method) {
        case 'get':
          return encrypted[name];
        case 'put':
          if (denyWrite) throw PlatformException(code: 'CREDENTIAL_VAULT');
          encrypted[name] = args['value'] as String;
          return true;
        case 'delete':
          encrypted.remove(name);
          return true;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SecretStore.channel, null);
  });

  test('legacy plaintext is migrated only after verified encrypted readback', () async {
    SharedPreferences.setMockInitialValues({'genius_key': 'fixture-only'});
    final prefs = await SharedPreferences.getInstance();
    expect(await SecretStore.read(prefs, 'genius_key'), 'fixture-only');
    expect(encrypted['genius_key'], 'fixture-only');
    expect(prefs.containsKey('genius_key'), isFalse);
    expect(await SecretStore.read(prefs, 'genius_key'), 'fixture-only');
  });

  test('vault failure retains sole legacy copy, never reports successful migration', () async {
    SharedPreferences.setMockInitialValues({'acr_secret': 'fixture-only'});
    final prefs = await SharedPreferences.getInstance();
    denyWrite = true;
    await expectLater(
      SecretStore.read(prefs, 'acr_secret'),
      throwsA(isA<PlatformException>()),
    );
    expect(prefs.getString('acr_secret'), 'fixture-only');
  });

  test('writes and deletes survive a fresh pref access without plaintext', () async {
    final prefs = await SharedPreferences.getInstance();
    await SecretStore.write(prefs, 'hf_token', 'fake-token');
    expect(prefs.containsKey('hf_token'), isFalse);
    expect(await SecretStore.read(prefs, 'hf_token'), 'fake-token');
    await SecretStore.delete(prefs, 'hf_token');
    expect(await SecretStore.read(prefs, 'hf_token'), isEmpty);
  });

  test('unrecognized credential key cannot be passed to native vault', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      SecretStore.write(prefs, 'other-secret', 'bad'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
