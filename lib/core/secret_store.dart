// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecretStore {
  SecretStore._();

  static const MethodChannel channel = MethodChannel('com.sovereign.tagger/secrets');

  static const List<String> migratedKeys = [
    'pcloud_token', 'genius_key', 'acr_key', 'acr_secret', 'hf_token',
  ];

  static void _checkKey(String key) {
    if (!migratedKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Not an approved credential key');
    }
  }

  static Future<String> read(SharedPreferences prefs, String key) async {
    _checkKey(key);
    final stored = await channel.invokeMethod<String>('get', {'name': key});
    if (stored != null) {
      if (prefs.containsKey(key) && !await prefs.remove(key)) {
        throw StateError('Legacy secret cleanup failed for $key');
      }
      return stored;
    }
    final legacy = prefs.getString(key) ?? '';
    if (legacy.isEmpty) return '';
    await write(prefs, key, legacy);
    return legacy;
  }

  static Future<void> write(SharedPreferences prefs, String key, String value) async {
    _checkKey(key);
    if (value.isEmpty) {
      await delete(prefs, key);
      return;
    }
    final saved = await channel.invokeMethod<bool>('put', {'name': key, 'value': value});
    if (saved != true) throw StateError('Encrypted credential write failed for $key');
    final readback = await channel.invokeMethod<String>('get', {'name': key});
    if (readback != value) {
      throw StateError('Encrypted credential verification failed for $key');
    }
    if (prefs.containsKey(key) && !await prefs.remove(key)) {
      throw StateError('Legacy secret cleanup failed for $key');
    }
  }

  static Future<void> delete(SharedPreferences prefs, String key) async {
    _checkKey(key);
    final deleted = await channel.invokeMethod<bool>('delete', {'name': key});
    if (deleted != true) throw StateError('Encrypted credential deletion failed for $key');
    if (prefs.containsKey(key) && !await prefs.remove(key)) {
      throw StateError('Legacy secret cleanup failed for $key');
    }
  }
}
