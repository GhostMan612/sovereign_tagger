// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Playlist {
  final String id;
  String name;
  final List<String> paths;
  final int created;

  Playlist({required this.id, required this.name, required this.paths, required this.created});

  Map<String, Object> toJson() => {'id': id, 'name': name, 'paths': paths, 'created': created};

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: j['name']?.toString() ?? 'Playlist',
        paths: ((j['paths'] as List?) ?? const []).map((e) => e.toString()).toList(),
        created: (j['created'] as num?)?.toInt() ?? 0,
      );
}

class PlaylistStore {
  static const int _recentLimit = 150;
  static final ValueNotifier<List<Playlist>> playlists = ValueNotifier<List<Playlist>>([]);
  static final ValueNotifier<Set<String>> favorites = ValueNotifier<Set<String>>({});
  static final ValueNotifier<List<String>> recent = ValueNotifier<List<String>>([]);
  static bool _loaded = false;
  static Timer? _saveDebounce;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sovereign_library.json');
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      playlists.value = ((data['playlists'] as List?) ?? const []).whereType<Map>().map((m) => Playlist.fromJson(m.cast<String, dynamic>())).toList();
      favorites.value = ((data['favorites'] as List?) ?? const []).map((e) => e.toString()).toSet();
      recent.value = ((data['recent'] as List?) ?? const []).map((e) => e.toString()).toList();
    } catch (_) {}
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final f = await _file();
        final payload = jsonEncode({
          'playlists': playlists.value.map((p) => p.toJson()).toList(),
          'favorites': favorites.value.toList(),
          'recent': recent.value,
        });
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(payload, flush: true);
        await tmp.rename(f.path);
      } catch (_) {}
    });
  }

  static void _touchPlaylists() {
    playlists.value = List<Playlist>.from(playlists.value);
    _scheduleSave();
  }

  static Playlist create(String name, [List<String> paths = const []]) {
    final p = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim().isEmpty ? 'New Playlist' : name.trim(), paths: List<String>.from(paths), created: DateTime.now().millisecondsSinceEpoch);
    playlists.value = [...playlists.value, p];
    _scheduleSave();
    return p;
  }

  static void addTo(String id, List<String> paths) {
    for (final p in playlists.value) {
      if (p.id == id) {
        for (final path in paths) {
          if (!p.paths.contains(path)) p.paths.add(path);
        }
      }
    }
    _touchPlaylists();
  }

  static void removeFrom(String id, String path) {
    for (final p in playlists.value) {
      if (p.id == id) p.paths.remove(path);
    }
    _touchPlaylists();
  }

  static void reorder(String id, int oldIndex, int newIndex) {
    for (final p in playlists.value) {
      if (p.id != id) continue;
      if (oldIndex < 0 || oldIndex >= p.paths.length) return;
      final item = p.paths.removeAt(oldIndex);
      final target = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, p.paths.length);
      p.paths.insert(target, item);
    }
    _touchPlaylists();
  }

  static void rename(String id, String name) {
    for (final p in playlists.value) {
      if (p.id == id && name.trim().isNotEmpty) p.name = name.trim();
    }
    _touchPlaylists();
  }

  static void delete(String id) {
    playlists.value = playlists.value.where((p) => p.id != id).toList();
    _scheduleSave();
  }

  static bool isFavorite(String path) => favorites.value.contains(path);

  static void toggleFavorite(String path) {
    final next = Set<String>.from(favorites.value);
    if (!next.remove(path)) next.add(path);
    favorites.value = next;
    _scheduleSave();
  }

  static void recordPlay(String path) {
    final next = [path, ...recent.value.where((p) => p != path)];
    recent.value = next.length > _recentLimit ? next.sublist(0, _recentLimit) : next;
    _scheduleSave();
  }

  static void replacePath(String oldPath, String newPath) {
    if (oldPath == newPath) return;
    var changed = false;
    for (final p in playlists.value) {
      for (var i = 0; i < p.paths.length; i++) {
        if (p.paths[i] == oldPath) {
          p.paths[i] = newPath;
          changed = true;
        }
      }
    }
    if (favorites.value.contains(oldPath)) {
      favorites.value = {...favorites.value.where((p) => p != oldPath), newPath};
      changed = true;
    }
    if (recent.value.contains(oldPath)) {
      recent.value = recent.value.map((p) => p == oldPath ? newPath : p).toList();
      changed = true;
    }
    if (changed) _touchPlaylists();
  }

  static void forgetPaths(Set<String> paths) {
    for (final p in playlists.value) {
      p.paths.removeWhere(paths.contains);
    }
    favorites.value = favorites.value.where((p) => !paths.contains(p)).toSet();
    recent.value = recent.value.where((p) => !paths.contains(p)).toList();
    _touchPlaylists();
  }
}
