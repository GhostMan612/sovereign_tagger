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

  const CloudDownloadSummary({required this.succeeded, required this.failed, required this.cancelled});
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
    final audio = <CloudEntry>[];
    await _collectAudio(folder, audio, depth: 0);
    var succeeded = 0;
    var failed = 0;
    var cancelled = false;
    for (var i = 0; i < audio.length; i++) {
      if (isCancelled != null && isCancelled()) {
        cancelled = true;
        break;
      }
      final entry = audio[i];
      onFile?.call(entry.name, i, audio.length);
      try {
        await downloadEntry(entry, isCancelled: isCancelled);
        succeeded++;
      } catch (_) {
        failed++;
      }
    }
    onFile?.call('', audio.length, audio.length);
    return CloudDownloadSummary(succeeded: succeeded, failed: failed, cancelled: cancelled);
  }

  static Future<void> _collectAudio(CloudEntry folder, List<CloudEntry> out, {required int depth}) async {
    if (depth > 3 || out.length >= 500) return;
    final entries = await PCloudProvider.instance.listFolder(folderId: folder.id);
    for (final entry in entries) {
      if (entry.isFolder) {
        await _collectAudio(entry, out, depth: depth + 1);
      } else if (entry.isAudio) {
        out.add(entry);
      }
      if (out.length >= 500) return;
    }
  }

  static String displayName(String name) {
    return name.replaceAll(RegExp(r'\.(mp3|flac|m4a|wav|ogg|opus|aac)$', caseSensitive: false), '');
  }

  static bool get downloadByDefault => CloudSettings.policy == CloudPlaybackPolicy.downloadByDefault;
}
