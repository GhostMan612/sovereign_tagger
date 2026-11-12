// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_source.dart';

enum CloudScope { appFolder, wholeDrive }

class CloudSettings {
  static const String redirectUri = 'sovereigntagger://pcloud/callback';
  static const String authorizeHostUs = 'my.pcloud.com';
  static const String authorizeHostEu = 'e.pcloud.com';
  static const int defaultCacheMb = 1024;

  static const String _clientIdKey = 'pcloud_client_id';
  static const String _tokenKey = 'pcloud_token';
  static const String _hostKey = 'pcloud_api_host';
  static const String _locationKey = 'pcloud_location_id';
  static const String _authHostKey = 'pcloud_authorize_host';
  static const String _rootPathKey = 'pcloud_root_path';
  static const String _rootIdKey = 'pcloud_root_id';
  static const String _scopeKey = 'pcloud_scope';
  static const String _policyKey = 'pcloud_policy';
  static const String _cacheMbKey = 'pcloud_cache_mb';
  static const String _dataWarnedKey = 'pcloud_data_warned';

  static SharedPreferences? _prefs;
  static final Completer<void> _ready = Completer<void>();

  static final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  static final ValueNotifier<String> apiHostLabel = ValueNotifier<String>('');

  static String _clientId = '';
  static String _token = '';
  static String _apiHost = '';
  static int _locationId = 0;
  static String _authorizeHost = authorizeHostUs;
  static String _rootPath = '/';
  static int _rootId = 0;
  static CloudScope _scope = CloudScope.appFolder;
  static CloudPlaybackPolicy _policy = CloudPlaybackPolicy.streamByDefault;
  static int _cacheMb = defaultCacheMb;
  static bool _dataWarned = false;

  static bool get isReady => _ready.isCompleted;
  static Future<void> ready() => _ready.future;

  static String get clientId => _clientId;
  static String get token => _token;
  static String get apiHost => _apiHost;
  static int get locationId => _locationId;
  static String get authorizeHost => _authorizeHost;
  static String get rootFolderPath => _rootPath;
  static int get rootFolderId => _rootId;
  static CloudScope get scope => _scope;
  static CloudPlaybackPolicy get policy => _policy;
  static int get cacheMb => _cacheMb;
  static bool get dataWarned => _dataWarned;

  static bool get hasToken => _token.isNotEmpty;

  static Uri get authorizeUri => Uri.https(_authorizeHost, '/oauth2/authorize');

  static Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    _clientId = prefs.getString(_clientIdKey) ?? '';
    _token = prefs.getString(_tokenKey) ?? '';
    final storedHost = prefs.getString(_hostKey) ?? '';
    try {
      _apiHost = storedHost.isEmpty ? '' : CloudRegion.fromHost(storedHost).host;
      if (_apiHost.isEmpty) _token = '';
    } on ArgumentError {
      _apiHost = '';
      _token = '';
    }
    _locationId = prefs.getInt(_locationKey) ?? 0;
    _authorizeHost = prefs.getString(_authHostKey) ?? authorizeHostUs;
    _rootPath = prefs.getString(_rootPathKey) ?? '/';
    _rootId = prefs.getInt(_rootIdKey) ?? 0;
    _scope = (prefs.getString(_scopeKey) ?? 'app') == 'drive' ? CloudScope.wholeDrive : CloudScope.appFolder;
    _policy = (prefs.getString(_policyKey) ?? 'stream') == 'download' ? CloudPlaybackPolicy.downloadByDefault : CloudPlaybackPolicy.streamByDefault;
    _cacheMb = prefs.getInt(_cacheMbKey) ?? defaultCacheMb;
    _dataWarned = prefs.getBool(_dataWarnedKey) ?? false;
    _refreshNotifiers();
    if (!_ready.isCompleted) _ready.complete();
  }

  static Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static void _refreshNotifiers() {
    isConnected.value = _token.isNotEmpty;
    apiHostLabel.value = _apiHost.isEmpty
        ? ''
        : _apiHost == CloudRegion.eu.host
            ? 'EU'
            : 'US';
  }

  static Future<void> setClientId(String value) async {
    _clientId = value.trim();
    final prefs = await _ensurePrefs();
    await prefs.setString(_clientIdKey, _clientId);
  }

  static Future<void> setToken({required String token, required String apiHost, required int locationId}) async {
    final approvedHost = CloudRegion.fromHost(apiHost).host;
    _token = token;
    _apiHost = approvedHost;
    _locationId = locationId;
    final prefs = await _ensurePrefs();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_hostKey, approvedHost);
    await prefs.setInt(_locationKey, locationId);
    _refreshNotifiers();
  }

  static Future<void> setAuthorizeHost(String host) async {
    _authorizeHost = host == authorizeHostEu ? authorizeHostEu : authorizeHostUs;
    final prefs = await _ensurePrefs();
    await prefs.setString(_authHostKey, _authorizeHost);
  }

  static Future<void> setRootFolder({required String path, required int folderId}) async {
    _rootPath = path.isEmpty ? '/' : path;
    _rootId = folderId;
    final prefs = await _ensurePrefs();
    await prefs.setString(_rootPathKey, _rootPath);
    await prefs.setInt(_rootIdKey, _rootId);
  }

  static Future<void> setScope(CloudScope scope) async {
    _scope = scope;
    final prefs = await _ensurePrefs();
    await prefs.setString(_scopeKey, scope == CloudScope.wholeDrive ? 'drive' : 'app');
  }

  static Future<void> setPolicy(CloudPlaybackPolicy policy) async {
    _policy = policy;
    final prefs = await _ensurePrefs();
    await prefs.setString(_policyKey, policy == CloudPlaybackPolicy.downloadByDefault ? 'download' : 'stream');
  }

  static Future<void> setCacheMb(int mb) async {
    _cacheMb = mb.clamp(100, 8192);
    final prefs = await _ensurePrefs();
    await prefs.setInt(_cacheMbKey, _cacheMb);
  }

  static Future<void> markDataWarned() async {
    _dataWarned = true;
    final prefs = await _ensurePrefs();
    await prefs.setBool(_dataWarnedKey, true);
  }

  static Future<void> clearCredentials() async {
    _token = '';
    _apiHost = '';
    _locationId = 0;
    final prefs = await _ensurePrefs();
    await prefs.remove(_tokenKey);
    await prefs.remove(_hostKey);
    await prefs.remove(_locationKey);
    _refreshNotifiers();
  }
}
