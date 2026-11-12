// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'cloud_settings.dart';
import 'cloud_source.dart';

class PCloudAuthResult {
  final String token;
  final String apiHost;
  final int locationId;

  const PCloudAuthResult({required this.token, required this.apiHost, required this.locationId});
}

class PCloudProvider implements CloudSource {
  static final PCloudProvider instance = PCloudProvider._();

  PCloudProvider._();

  static const String _tokenFlow = 'token';

  @override
  String get providerId => 'pcloud';

  @override
  String get displayName => 'pCloud';

  @override
  bool get isAuthenticated => CloudSettings.hasToken;

  @override
  String get apiHost => CloudSettings.apiHost.isEmpty ? CloudRegion.us.host : CloudSettings.apiHost;

  @override
  String get rootFolderPath => CloudSettings.rootFolderPath;

  @override
  CloudPlaybackPolicy get defaultPlaybackPolicy => CloudSettings.policy;

  Uri buildAuthorizeUrl() {
    return CloudSettings.authorizeUri.replace(queryParameters: <String, String>{
      'client_id': CloudSettings.clientId,
      'response_type': _tokenFlow,
      'redirect_uri': CloudSettings.redirectUri,
    });
  }

  static PCloudAuthResult? parseAuthRedirect(String redirect) {
    final uri = Uri.tryParse(redirect);
    if (uri == null) return null;
    if (uri.scheme != 'sovereigntagger' || uri.host != 'pcloud') return null;
    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    final params = Uri.splitQueryString(fragment);
    final token = params['access_token'] ?? '';
    if (token.isEmpty) return null;
    final locationId = int.tryParse(params['locationid'] ?? '') ?? 0;
    final hostname = params['hostname'] ?? '';
    final host = hostname.isNotEmpty ? hostname : (locationId == 2 ? CloudRegion.eu.host : CloudRegion.us.host);
    return PCloudAuthResult(token: token, apiHost: host, locationId: locationId);
  }

  Future<Map<String, dynamic>> _call(String method, Map<String, String> params) async {
    if (!CloudSettings.hasToken) {
      throw const PCloudException('NOT CONNECTED — SIGN IN TO PCLOUD IN SETTINGS FIRST.');
    }
    final query = <String, String>{'auth': CloudSettings.token, ...params};
    final uri = Uri.https(apiHost, '/$method', query);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0 (Android; pCloud)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw PCloudException('PCLOUD ANSWERED HTTP ${response.statusCode} — TRY AGAIN WHEN YOU HAVE SIGNAL.');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const PCloudException('PCLOUD ANSWERED IN A FORM I CANNOT READ — TRY AGAIN.');
      }
      final result = decoded['result'];
      if (result != 0) {
        throw PCloudException(_plainError(result is int ? result : -1));
      }
      return decoded;
    } on PCloudException {
      rethrow;
    } on SocketException {
      throw const PCloudException('NO CONNECTION TO PCLOUD — CHECK SIGNAL, THEN RETRY.');
    } on HttpException {
      throw const PCloudException('PCLOUD DID NOT ANSWER — CHECK SIGNAL, THEN RETRY.');
    } on FormatException {
      throw const PCloudException('PCLOUD ANSWERED IN A FORM I CANNOT READ — TRY AGAIN.');
    } finally {
      client.close();
    }
  }

  static String _plainError(int code) {
    switch (code) {
      case 1000:
        return 'PCLOUD SAYS THE SIGN-IN IS MISSING OR EXPIRED — RECONNECT IN SETTINGS.';
      case 2000:
      case 2001:
      case 2002:
        return 'PCLOUD CANNOT FIND THAT FILE OR FOLDER ANY MORE.';
      case 2094:
        return 'PCLOUD REJECTED THE SIGN-IN TOKEN — RECONNECT IN SETTINGS.';
      case 4000:
        return 'PCLOUD IS TOO BUSY RIGHT NOW — RETRY IN A MOMENT.';
      case 5000:
        return 'PCLOUD IS HAVING TROUBLE ON ITS SIDE — RETRY LATER.';
      default:
        return 'PCLOUD SAID NO (CODE $code) — CHECK THE CONNECTION AND RETRY.';
    }
  }

  @override
  Future<List<CloudEntry>> listFolder({String? folderId, String? folderPath}) async {
    final params = <String, String>{};
    if (folderId != null && folderId.isNotEmpty && folderId != '0') {
      params['folderid'] = folderId;
    } else if (folderPath != null && folderPath.isNotEmpty && folderPath != '/') {
      params['path'] = folderPath;
    } else {
      params['folderid'] = '0';
    }
    final decoded = await _call('listfolder', params);
    final metadata = decoded['metadata'];
    if (metadata is! Map<String, dynamic>) return const [];
    final contents = metadata['contents'];
    if (contents is! List) return const [];
    final parentId = metadata['folderid']?.toString() ?? folderId ?? '0';
    final entries = <CloudEntry>[];
    for (final item in contents) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final isFolder = item['isfolder'] == true;
      final id = isFolder ? (item['folderid']?.toString() ?? '') : (item['fileid']?.toString() ?? '');
      if (id.isEmpty) continue;
      final modified = item['modified'];
      entries.add(CloudEntry(
        id: id,
        parentFolderId: parentId,
        name: name,
        path: item['path']?.toString() ?? '',
        isFolder: isFolder,
        sizeBytes: item['size'] is int ? item['size'] as int : 0,
        contentType: item['contenttype']?.toString() ?? '',
        modifiedUnix: modified is int ? modified : 0,
      ));
    }
    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<Uri?> resolveStreamUri(String fileId) async {
    try {
      final decoded = await _call('getfilelink', <String, String>{'fileid': fileId});
      final hosts = decoded['hosts'];
      final path = decoded['path']?.toString() ?? '';
      if (hosts is! List || hosts.isEmpty || path.isEmpty) return null;
      final host = hosts.first.toString();
      if (host.isEmpty) return null;
      return Uri.parse('https://$host$path');
    } on PCloudException {
      return null;
    }
  }

  @override
  Future<String?> downloadToFile({
    required String fileId,
    required String destinationPath,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final streamUri = await resolveStreamUri(fileId);
    if (streamUri == null) {
      throw const PCloudException('PCLOUD WOULD NOT HAND OVER A DOWNLOAD LINK FOR THAT FILE.');
    }
    final target = File(destinationPath);
    final part = File('$destinationPath.part');
    if (part.existsSync()) await part.delete();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      var current = streamUri;
      HttpClientResponse? response;
      for (var hop = 0; hop < 10; hop++) {
        if (isCancelled != null && isCancelled()) {
          throw const PCloudException('DOWNLOAD CANCELLED.');
        }
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0 (Android; pCloud)');
        final resp = await request.close();
        final code = resp.statusCode;
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          final location = resp.headers.value(HttpHeaders.locationHeader);
          await resp.drain<void>();
          if (location == null || location.isEmpty) {
            throw const PCloudException('PCLOUD SENT A DOWNLOAD LINK THAT GOES NOWHERE.');
          }
          current = current.resolve(location);
          continue;
        }
        response = resp;
        break;
      }
      final resp = response;
      if (resp == null) throw const PCloudException('PCLOUD DID NOT ANSWER THE DOWNLOAD.');
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw PCloudException('PCLOUD ANSWERED HTTP ${resp.statusCode} FOR THE DOWNLOAD.');
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in resp) {
          if (isCancelled != null && isCancelled()) {
            throw const PCloudException('DOWNLOAD CANCELLED.');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw PCloudException('DOWNLOAD INCOMPLETE — RECEIVED $received OF $total BYTES. RETRY.');
      }
      if (!part.existsSync() || part.lengthSync() == 0) {
        if (part.existsSync()) await part.delete();
        throw const PCloudException('THE DOWNLOAD ARRIVED EMPTY — RETRY.');
      }
      await part.rename(target.path);
      return target.path;
    } on PCloudException {
      if (part.existsSync()) await part.delete();
      rethrow;
    } on SocketException {
      if (part.existsSync()) await part.delete();
      throw const PCloudException('NO CONNECTION TO PCLOUD — CHECK SIGNAL, THEN RETRY.');
    } finally {
      client.close();
    }
  }

  Future<bool> testConnection() async {
    try {
      await listFolder(folderId: '0');
      return true;
    } on PCloudException {
      return false;
    }
  }

  Future<void> logoutRemote() async {
    try {
      await _call('logout', const <String, String>{});
    } on PCloudException {
      return;
    }
  }

  @override
  Future<void> signOut() async {
    await logoutRemote();
    await CloudSettings.clearCredentials();
  }
}

class PCloudException implements Exception {
  final String message;
  const PCloudException(this.message);
  @override
  String toString() => message;
}
