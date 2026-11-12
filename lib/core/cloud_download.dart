// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'cloud_cache.dart';
import 'cloud_pcloud.dart';
import 'cloud_source.dart';
import 'cloud_settings.dart';
import 'storage_client.dart';

class CloudDownloadSummary {
  final int succeeded;
  final int failed;
  final bool cancelled;
  final bool truncated;
  final String truncationReason;

  const CloudDownloadSummary({
    required this.succeeded,
    required this.failed,
    required this.cancelled,
    this.truncated = false,
    this.truncationReason = '',
  });
}

class CloudFolderScanResult {
  final List<CloudEntry> audio;
  final bool truncated;
  final bool cancelled;
  final String truncationReason;

  const CloudFolderScanResult({
    required this.audio,
    required this.truncated,
    required this.cancelled,
    required this.truncationReason,
  });
}

class CloudDownload {
  static Future<File> _stagePath(String fileId, String name) async {
    final temp = await StorageClient.tempDir();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final stageDir = await Directory(temp).createTemp('cloud_dl_');
    final fileName = safe.isEmpty || safe == '.' || safe == '..' ? 'cloud_media' : safe;
    return File('${stageDir.path}/$fileName');
  }

  static Future<SaveResult> downloadEntry(
    CloudEntry entry, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stage = await _stagePath(entry.id, entry.name);
    try {
      final downloadedPath = await PCloudProvider.instance.downloadToFile(
        fileId: entry.id,
        destinationPath: stage.path,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (downloadedPath == null) {
        throw const PCloudException('THE DOWNLOAD ARRIVED EMPTY — RETRY.');
      }
      final saved = await StorageClient.exportToLibrary(downloadedPath, entry.name);
      return saved;
    } finally {
      if (await stage.parent.exists()) await stage.parent.delete(recursive: true);
    }
  }

  static Future<SaveResult> downloadForOffline(
    CloudEntry entry, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
    Set<String> protectedCachePaths = const <String>{},
  }) async {
    final stage = await _stagePath(entry.id, entry.name);
    try {
      final downloadedPath = await PCloudProvider.instance.downloadToFile(
        fileId: entry.id,
        destinationPath: stage.path,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (downloadedPath == null) {
        throw const PCloudException('THE DOWNLOAD ARRIVED EMPTY — RETRY.');
      }
      final cached = await CloudCache.put(entry.id, entry.name, File(downloadedPath), protectedPaths: protectedCachePaths);
      return SaveResult(uri: '', path: cached.path, displayName: entry.name, overwroteOriginal: false, renamed: false);
    } finally {
      if (await stage.parent.exists()) await stage.parent.delete(recursive: true);
    }
  }

  static Future<CloudDownloadSummary> downloadFolder(
    CloudEntry folder, {
    void Function(String name, int done, int total)? onFile,
    bool Function()? isCancelled,
  }) async {
    final scan = await scanFolder(folder, isCancelled: isCancelled);
    var succeeded = 0;
    var failed = 0;
    var cancelled = scan.cancelled;
    for (var i = 0; i < scan.audio.length; i++) {
      if (isCancelled != null && isCancelled()) {
        cancelled = true;
        break;
      }
      final entry = scan.audio[i];
      onFile?.call(entry.name, i, scan.audio.length);
      try {
        await downloadEntry(entry, isCancelled: isCancelled);
        succeeded++;
      } catch (_) {
        if (isCancelled != null && isCancelled()) {
          cancelled = true;
          break;
        }
        failed++;
      }
    }
    onFile?.call('', succeeded + failed, scan.audio.length);
    return CloudDownloadSummary(
      succeeded: succeeded,
      failed: failed,
      cancelled: cancelled,
      truncated: scan.truncated,
      truncationReason: scan.truncationReason,
    );
  }

  static Future<CloudFolderScanResult> scanFolder(
    CloudEntry folder, {
    Future<List<CloudEntry>> Function(String folderId)? listEntries,
    bool Function()? isCancelled,
    int maxDepth = 3,
    int maxAudio = 500,
  }) async {
    if (maxDepth < 0 || maxAudio < 1) {
      throw ArgumentError('Folder scan limits must be positive.');
    }
    final fetch = listEntries ??
        (String id) => PCloudProvider.instance.listFolder(folderId: id);
    final audio = <CloudEntry>[];
    final visitedFolders = <String>{};
    final seenFiles = <String>{};
    var cancelled = false;
    var truncated = false;
    var reason = '';

    Future<void> visit(CloudEntry current, int depth) async {
      if (cancelled || truncated) return;
      if (isCancelled != null && isCancelled()) {
        cancelled = true;
        return;
      }
      if (depth > maxDepth) {
        truncated = true;
        reason = 'Folder depth limit reached ($maxDepth).';
        return;
      }
      if (!visitedFolders.add(current.id)) return;
      final children = await fetch(current.id);
      for (final child in children) {
        if (isCancelled != null && isCancelled()) {
          cancelled = true;
          return;
        }
        if (child.isFolder) {
          await visit(child, depth + 1);
        } else if (child.isAudio && seenFiles.add(child.id)) {
          audio.add(child);
          if (audio.length >= maxAudio) {
            truncated = true;
            reason = 'Folder audio limit reached ($maxAudio files).';
          }
        }
        if (cancelled || truncated) return;
      }
    }

    await visit(folder, 0);
    return CloudFolderScanResult(
      audio: List<CloudEntry>.unmodifiable(audio),
      truncated: truncated,
      cancelled: cancelled,
      truncationReason: reason,
    );
  }

  static String displayName(String name) {
    return name.replaceAll(RegExp(r'\.(mp3|flac|m4a|wav|ogg|opus|aac)$', caseSensitive: false), '');
  }

  static bool get downloadByDefault => CloudSettings.policy == CloudPlaybackPolicy.downloadByDefault;
}
