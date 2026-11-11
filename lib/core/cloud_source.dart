// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

enum CloudRegion {
  us('api.pcloud.com'),
  eu('eapi.pcloud.com');

  final String host;
  const CloudRegion(this.host);

  static CloudRegion fromHost(String rawHost) {
    final host = rawHost.trim().toLowerCase();
    if (host == CloudRegion.eu.host) return CloudRegion.eu;
    if (host == CloudRegion.us.host) return CloudRegion.us;
    throw ArgumentError.value(rawHost, 'rawHost', 'Unsupported pCloud API host');
  }
}

enum CloudPlaybackPolicy {
  streamByDefault,
  downloadByDefault,
}

class CloudEntry {
  final String id;
  final String parentFolderId;
  final String name;
  final String path;
  final bool isFolder;
  final int sizeBytes;
  final String contentType;
  final int modifiedUnix;

  const CloudEntry({
    required this.id,
    required this.parentFolderId,
    required this.name,
    required this.path,
    required this.isFolder,
    this.sizeBytes = 0,
    this.contentType = '',
    this.modifiedUnix = 0,
  });

  bool get isAudio {
    if (isFolder) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.aac');
  }
}

abstract class CloudSource {
  String get providerId;
  String get displayName;
  bool get isAuthenticated;
  String get apiHost;
  String get rootFolderPath;
  CloudPlaybackPolicy get defaultPlaybackPolicy;

  Future<List<CloudEntry>> listFolder({String? folderId, String? folderPath});
  Future<Uri?> resolveStreamUri(String fileId);
  Future<String?> downloadToFile({
    required String fileId,
    required String destinationPath,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });

  Future<void> signOut();
}
