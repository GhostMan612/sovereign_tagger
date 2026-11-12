// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class PendingWorkbenchImport {
  const PendingWorkbenchImport({
    required this.id,
    required this.title,
    required this.fileName,
    required this.filePath,
    required this.bytes,
    required this.sha256Hex,
    required this.createdAt,
    required this.available,
  });

  final String id;
  final String title;
  final String fileName;
  final String filePath;
  final int bytes;
  final String sha256Hex;
  final DateTime createdAt;
  final bool available;

  Map<String, Object> toJson() => {
        'v': 1,
        'id': id,
        'title': title,
        'fileName': fileName,
        'bytes': bytes,
        'sha256': sha256Hex,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

class PendingImportStore {
  PendingImportStore(this.appSupportDirectory);

  final Directory appSupportDirectory;

  Directory get _root =>
      Directory('${appSupportDirectory.path}/workbench_pending_imports');

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,160}$');
  static final RegExp _safeExt = RegExp(r'^[a-zA-Z0-9]{1,8}$');

  Future<void> initialize() async {
    await _root.create(recursive: true);
  }

  File _payload(String id, String ext) =>
      File('${_root.path}/$id.$ext');

  File _manifest(String id) => File('${_root.path}/$id.json');

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<PendingWorkbenchImport> preserve({
    required File staged,
    required String jobId,
    required String title,
  }) async {
    await initialize();
    if (!await staged.exists() || await staged.length() == 0) {
      throw const FileSystemException('Rendered output is missing or empty');
    }
    final unique = '${jobId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_${DateTime.now().microsecondsSinceEpoch}';
    if (!_safeId.hasMatch(unique)) {
      throw const FormatException('Untrusted pending import identifier');
    }
    final ext = staged.path.split('.').last.toLowerCase();
    if (!_safeExt.hasMatch(ext)) {
      throw const FormatException('Unsupported pending file extension');
    }
    final output = _payload(unique, ext);
    final part = File('${output.path}.part');
    final manifest = _manifest(unique);
    final manifestPart = File('${manifest.path}.part');
    final bytes = await staged.length();
    final expected = await _hash(staged);
    try {
      await staged.copy(part.path);
      if (await part.length() != bytes || await _hash(part) != expected) {
        throw const FileSystemException('Recovery staging digest mismatch');
      }
      await part.rename(output.path);
      final entry = PendingWorkbenchImport(
        id: unique,
        title: title,
        fileName: output.uri.pathSegments.last,
        filePath: output.path,
        bytes: bytes,
        sha256Hex: expected,
        createdAt: DateTime.now().toUtc(),
        available: true,
      );
      await manifestPart.writeAsString(jsonEncode(entry.toJson()), flush: true);
      await manifestPart.rename(manifest.path);
      return entry;
    } finally {
      if (await part.exists()) await part.delete();
      if (await manifestPart.exists()) await manifestPart.delete();
    }
  }

  Future<List<PendingWorkbenchImport>> list() async {
    await initialize();
    final out = <PendingWorkbenchImport>[];
    await for (final entity in _root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        if (data['v'] != 1) continue;
        final id = data['id'] as String? ?? '';
        final name = data['fileName'] as String? ?? '';
        if (!_safeId.hasMatch(id) ||
            name.contains('/') ||
            name.contains('\\') ||
            !name.startsWith('$id.')) {
          continue;
        }
        final path = '${_root.path}/$name';
        final file = File(path);
        final expectedBytes = data['bytes'] as int? ?? 0;
        final expectedSha = data['sha256'] as String? ?? '';
        final exists = await file.exists();
        final valid = exists &&
            expectedBytes > 0 &&
            await file.length() == expectedBytes &&
            await _hash(file) == expectedSha;
        out.add(PendingWorkbenchImport(
          id: id,
          title: data['title'] as String? ?? name,
          fileName: name,
          filePath: path,
          bytes: expectedBytes,
          sha256Hex: expectedSha,
          createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          available: valid,
        ));
      } on FormatException {
        // Invalid manifests are never imported or erased automatically.
      } on TypeError {
        // Existing manifests remain inspectable for manual recovery.
      } on FileSystemException {
        // Storage failures are handled by caller on actual retry.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<String> retry(
    PendingWorkbenchImport item,
    Future<String?> Function(String path, String title) importer,
  ) async {
    final current = (await list()).where((i) => i.id == item.id).toList();
    if (current.isEmpty || !current.single.available) {
      throw StateError('Recovery file is missing or failed its SHA-256 integrity check');
    }
    final uri = (await importer(current.single.filePath, current.single.title))?.trim();
    if (uri == null || uri.isEmpty || !uri.startsWith('content://')) {
      throw StateError('MediaStore did not return a committed media content URI');
    }
    await discard(item);
    return uri;
  }

  Future<void> discard(PendingWorkbenchImport item) async {
    if (!_safeId.hasMatch(item.id)) {
      throw ArgumentError('Invalid recovery identifier');
    }
    final entries = await list();
    final found = entries.where((e) => e.id == item.id).toList();
    if (found.isEmpty) throw StateError('Pending import no longer exists');
    final file = File(found.single.filePath);
    if (await file.exists()) await file.delete();
    final manifest = _manifest(item.id);
    if (await manifest.exists()) await manifest.delete();
  }
}
