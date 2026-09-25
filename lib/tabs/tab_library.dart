// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/forge_request.dart';
import '../core/playlists.dart';
import '../core/storage_client.dart';
import '../screens/main_shell.dart';
import '../widgets/playlist_picker.dart';

class LibTrack {
  final String uri;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int albumId;
  final int durationMs;
  final int track;
  final int disc;
  final int year;
  final int dateAdded;
  final String displayName;

  const LibTrack({
    required this.uri,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.albumId,
    required this.durationMs,
    required this.track,
    required this.disc,
    required this.year,
    required this.dateAdded,
    required this.displayName,
  });

  static String _clean(Object? v, String fallback) {
    final s = v?.toString().trim() ?? '';
    return (s.isEmpty || s == '<unknown>') ? fallback : s;
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  factory LibTrack.fromMap(Map<String, Object?> m) {
    final display = m['displayName']?.toString() ?? '';
    final base = display.contains('.') ? display.substring(0, display.lastIndexOf('.')) : display;
    final artist = _clean(m['artist'], 'Unknown Artist');
    return LibTrack(
      uri: m['uri']?.toString() ?? '',
      path: m['path']?.toString() ?? '',
      title: _clean(m['title'], base.isEmpty ? 'Untitled' : base),
      artist: artist,
      album: _clean(m['album'], 'Unknown Album'),
      albumArtist: _clean(m['albumArtist'], artist),
      albumId: _int(m['albumId']),
      durationMs: _int(m['durationMs']),
      track: _int(m['track']),
      disc: _int(m['disc']),
      year: _int(m['year']),
      dateAdded: _int(m['dateAdded']),
      displayName: display,
    );
  }

  String get folder {
    final i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : '/';
  }

  TrackInfo toInfo() => TrackInfo(title: title, artist: artist, album: album, uri: uri, durationMs: durationMs);
}

class LibraryArt {
  static final Map<String, Future<ImageProvider?>> _cache = {};
  static const int _limit = 400;

  static Future<ImageProvider?> load(String uri) {
    final existing = _cache.remove(uri);
    if (existing != null) {
      _cache[uri] = existing;
      return existing;
    }
    final f = StorageClient.loadArtwork(uri, size: 256).then<ImageProvider?>((bytes) => bytes == null || bytes.isEmpty ? null : MemoryImage(bytes));
    _cache[uri] = f;
    if (_cache.length > _limit) _cache.remove(_cache.keys.first);
    return f;
  }

  static void evict(String uri) => _cache.remove(uri);
}

class _ArtThumb extends StatelessWidget {
  final String uri;
  final double size;
  final Color color;
  const _ArtThumb({required this.uri, required this.color, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<ImageProvider?>(
          future: uri.isEmpty ? Future.value(null) : LibraryArt.load(uri),
          builder: (context, snap) {
            final img = snap.data;
            if (img == null) {
              return Container(color: color.withValues(alpha: 0.08), child: Icon(Icons.music_note, color: color.withValues(alpha: 0.6), size: size * 0.5));
            }
            return Image(image: img, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}

enum _View { songs, albums, artists, folders, playlists, recent }

enum _Sort { title, artist, album, added, duration }

class _Detail {
  final String title;
  final List<LibTrack> tracks;
  final String? playlistId;
  final bool keepOrder;
  const _Detail(this.title, this.tracks, {this.playlistId, this.keepOrder = false});
}

class TabLibrary extends StatefulWidget {
  const TabLibrary({super.key});

  @override
  State<TabLibrary> createState() => _TabLibraryState();
}

class _TabLibraryState extends State<TabLibrary> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  List<LibTrack> _all = [];
  Map<String, LibTrack> _byPath = {};
  bool _loading = false;
  bool _permissionDenied = false;
  bool _loadedOnce = false;
  String _status = "";
  _View _view = _View.songs;
  _Sort _sort = _Sort.title;
  _Detail? _detail;
  Timer? _refreshDebounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    StorageClient.libraryRevision.addListener(_scheduleRefresh);
    SovereignState.currentTab.addListener(_onTab);
    PlaylistStore.load().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTab());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    StorageClient.libraryRevision.removeListener(_scheduleRefresh);
    SovereignState.currentTab.removeListener(_onTab);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTab() {
    if (SovereignState.currentTab.value == 4 && !_loadedOnce) _scan();
    if (_detail != null && mounted) setState(() {});
  }

  void _scheduleRefresh() {
    if (!_loadedOnce) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 1500), () => _scan(silent: true));
  }

  Future<bool> _ensurePermission() async {
    final sdk = await StorageClient.sdkInt();
    final permission = sdk >= 33 ? Permission.audio : Permission.storage;
    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _scan({bool silent = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (!silent) _status = "Scanning Music Library...";
    });
    try {
      if (!await _ensurePermission()) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _permissionDenied = true;
          _status = "Music permission denied.";
        });
        return;
      }
      final rows = await StorageClient.queryAudio();
      final tracks = rows.map(LibTrack.fromMap).where((t) => t.path.isNotEmpty).toList();
      for (final t in tracks) {
        AudioService.registerInfo(t.path, t.toInfo());
      }
      if (!mounted) return;
      setState(() {
        _all = tracks;
        _byPath = {for (final t in tracks) t.path: t};
        _loading = false;
        _loadedOnce = true;
        _permissionDenied = false;
        _status = "${tracks.length} tracks";
        if (_detail != null && _detail!.playlistId == null) _detail = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = "ERR: Library scan fault: $e";
      });
    }
  }

  String _q() => _searchCtrl.text.trim().toLowerCase();

  bool _matches(LibTrack t, String q) => q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q);

  List<LibTrack> _sorted(List<LibTrack> list) {
    final out = List<LibTrack>.from(list);
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    switch (_sort) {
      case _Sort.title:
        out.sort((a, b) => byText(a.title, b.title));
        break;
      case _Sort.artist:
        out.sort((a, b) {
          final c = byText(a.artist, b.artist);
          return c != 0 ? c : byText(a.title, b.title);
        });
        break;
      case _Sort.album:
        out.sort((a, b) {
          final c = byText(a.album, b.album);
          if (c != 0) return c;
          final d = a.disc.compareTo(b.disc);
          return d != 0 ? d : a.track.compareTo(b.track);
        });
        break;
      case _Sort.added:
        out.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case _Sort.duration:
        out.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        break;
    }
    return out;
  }

  List<LibTrack> _albumOrder(List<LibTrack> list) {
    final out = List<LibTrack>.from(list);
    out.sort((a, b) {
      final d = a.disc.compareTo(b.disc);
      if (d != 0) return d;
      final t = a.track.compareTo(b.track);
      return t != 0 ? t : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  List<LibTrack> _resolvePaths(List<String> paths) {
    final out = <LibTrack>[];
    for (final p in paths) {
      final t = _byPath[p];
      if (t != null) {
        out.add(t);
      } else if (File(p).existsSync()) {
        final name = p.split('/').last;
        out.add(LibTrack(uri: '', path: p, title: name, artist: '', album: '', albumArtist: '', albumId: 0, durationMs: 0, track: 0, disc: 0, year: 0, dateAdded: 0, displayName: name));
      }
    }
    return out;
  }

  Future<void> _play(List<LibTrack> list, int index, {bool shuffle = false}) async {
    if (list.isEmpty) return;
    for (final t in list) {
      AudioService.registerInfo(t.path, t.toInfo());
    }
    AudioService.isShuffle.value = shuffle;
    await AudioService.playFiles(list.map((t) => File(t.path)).toList(), startIndex: shuffle ? Random().nextInt(list.length) : index);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'ShareTechMono'))));
  }

  Future<void> _deleteTracks(List<LibTrack> tracks) async {
    final themeColor = SovereignState.accentColor.value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(6)),
        title: const Text("DELETE FROM DEVICE?", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(tracks.length == 1 ? "\"${tracks.first.title}\" will be permanently deleted from this phone." : "${tracks.length} tracks will be permanently deleted from this phone.", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text("KEEP", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.black), onPressed: () => Navigator.pop(d, true), child: const Text("DELETE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;
    final uris = tracks.map((t) => t.uri).where((u) => u.isNotEmpty).toList();
    final granted = await StorageClient.requestDelete(uris);
    if (!granted) {
      _toast("> DELETE CANCELLED.");
      return;
    }
    final paths = tracks.map((t) => t.path).toSet();
    await AudioService.removePathsFromQueue(paths);
    PlaylistStore.forgetPaths(paths);
    if (!mounted) return;
    setState(() {
      _all = _all.where((t) => !paths.contains(t.path)).toList();
      _byPath.removeWhere((k, _) => paths.contains(k));
      if (_detail != null) {
        final remaining = _detail!.tracks.where((t) => !paths.contains(t.path)).toList();
        _detail = _Detail(_detail!.title, remaining, playlistId: _detail!.playlistId, keepOrder: _detail!.keepOrder);
      }
    });
    _toast("> DELETED ${paths.length} TRACK(S).");
  }

  void _trackMenu(LibTrack t, List<LibTrack> list, int index, Color themeColor) {
    final playlistId = _detail?.playlistId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.97),
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: themeColor.withValues(alpha: 0.5))),
      builder: (sheet) {
        final fav = PlaylistStore.isFavorite(t.path);
        Widget tile(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? themeColor),
              title: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', color: color ?? Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(sheet);
                onTap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: _ArtThumb(uri: t.uri, color: themeColor),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text("${t.artist} • ${t.album}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                ),
                const Divider(color: Colors.white12, height: 1),
                tile(Icons.play_arrow, "PLAY", () => _play(list, index)),
                tile(Icons.low_priority, "PLAY NEXT", () {
                  AudioService.registerInfo(t.path, t.toInfo());
                  AudioService.playNext(File(t.path));
                  _toast("> QUEUED NEXT: ${t.title}");
                }),
                tile(Icons.queue, "ADD TO QUEUE", () {
                  AudioService.registerInfo(t.path, t.toInfo());
                  AudioService.addToQueue(File(t.path));
                  _toast("> ADDED TO QUEUE: ${t.title}");
                }),
                tile(fav ? Icons.favorite : Icons.favorite_border, fav ? "REMOVE FROM FAVORITES" : "ADD TO FAVORITES", () {
                  PlaylistStore.toggleFavorite(t.path);
                  setState(() {});
                }, color: Colors.pinkAccent),
                tile(Icons.playlist_add, "ADD TO PLAYLIST", () => showPlaylistPicker(context, [t.path], themeColor)),
                if (playlistId != null && playlistId.startsWith('user:'))
                  tile(Icons.playlist_remove, "REMOVE FROM THIS PLAYLIST", () {
                    PlaylistStore.removeFrom(playlistId.substring(5), t.path);
                    _refreshPlaylistDetail();
                  }),
                tile(Icons.edit_note, "EDIT IN FORGE", () => SovereignState.sendToForge(ForgeRequest(path: t.path, origin: ForgeOrigin.library, originUri: t.uri.isEmpty ? null : t.uri)), color: Colors.purpleAccent),
                if (t.uri.isNotEmpty) tile(Icons.delete_forever, "DELETE FROM DEVICE", () => _deleteTracks([t]), color: Colors.redAccent),
              ],
            ),
          ),
        );
      },
    );
  }

  void _refreshPlaylistDetail() {
    final d = _detail;
    if (d == null || d.playlistId == null) return;
    setState(() => _detail = _playlistDetail(d.playlistId!));
  }

  _Detail _playlistDetail(String id) {
    if (id == 'fav') return _Detail("FAVORITES", _resolvePaths(PlaylistStore.favorites.value.toList()), playlistId: id, keepOrder: false);
    if (id == 'recent') return _Detail("RECENTLY PLAYED", _resolvePaths(PlaylistStore.recent.value), playlistId: id, keepOrder: true);
    final p = PlaylistStore.playlists.value.firstWhere((p) => 'user:${p.id}' == id, orElse: () => Playlist(id: '', name: 'Playlist', paths: [], created: 0));
    return _Detail(p.name, _resolvePaths(p.paths), playlistId: id, keepOrder: true);
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? "$h:$m:$s" : "$m:$s";
  }

  Widget _trackTile(LibTrack t, List<LibTrack> list, int index, Color themeColor, {Widget? trailing}) {
    return ValueListenableBuilder<int>(
      valueListenable: AudioService.currentIndex,
      builder: (context, _, __) {
        final idx = AudioService.currentIndex.value;
        final playing = idx >= 0 && idx < AudioService.playlist.value.length && AudioService.playlist.value[idx].path == t.path;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: _ArtThumb(uri: t.uri, color: themeColor),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', color: playing ? themeColor : Colors.white, fontSize: 14, fontWeight: playing ? FontWeight.bold : FontWeight.normal)),
          subtitle: Text("${t.artist} • ${t.album}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
          trailing: trailing ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.durationMs > 0) Text(_fmt(t.durationMs), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                  IconButton(icon: const Icon(Icons.more_vert, color: Colors.white54), onPressed: () => _trackMenu(t, list, index, themeColor)),
                ],
              ),
          onTap: () => _play(list, index),
          onLongPress: () => _trackMenu(t, list, index, themeColor),
        );
      },
    );
  }

  Widget _playBar(List<LibTrack> list, Color themeColor) {
    final total = list.fold<int>(0, (a, t) => a + t.durationMs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(child: Text("${list.length} TRACKS${total > 0 ? ' • ${_fmt(total)}' : ''}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54))),
          OutlinedButton.icon(
            onPressed: list.isEmpty ? null : () => _play(list, 0, shuffle: true),
            icon: Icon(Icons.shuffle, size: 16, color: themeColor),
            label: Text("SHUFFLE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor.withValues(alpha: 0.5)), visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: list.isEmpty ? null : () => _play(list, 0),
            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.black),
            label: const Text("PLAY ALL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: themeColor, visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _songs(Color themeColor, List<LibTrack> source) {
    final q = _q();
    final list = _sorted(source.where((t) => _matches(t, q)).toList());
    return Column(
      children: [
        _playBar(list, themeColor),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => _trackTile(list[i], list, i, themeColor),
          ),
        ),
      ],
    );
  }

  Widget _groupList(Color themeColor, Map<String, List<LibTrack>> groups, IconData icon, {bool albumOrder = false, bool showArt = false, bool folderMode = false, String Function(String key, List<LibTrack> v)? subtitle}) {
    final q = _q();
    final keys = groups.keys.where((k) => q.isEmpty || k.toLowerCase().contains(q) || groups[k]!.any((t) => _matches(t, q))).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (keys.isEmpty) return _empty(themeColor, "NOTHING MATCHES");
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final tracks = groups[key]!;
        final label = folderMode && key.split('/').last.isNotEmpty ? key.split('/').last : key;
        return ListTile(
          leading: showArt ? _ArtThumb(uri: tracks.first.uri, color: themeColor) : Icon(icon, color: themeColor),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
          subtitle: Text(subtitle?.call(key, tracks) ?? "${tracks.length} tracks", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () => setState(() => _detail = _Detail(label, albumOrder ? _albumOrder(tracks) : _sorted(tracks), keepOrder: albumOrder)),
        );
      },
    );
  }

  Widget _albums(Color themeColor) {
    final groups = <String, List<LibTrack>>{};
    for (final t in _all) {
      groups.putIfAbsent("${t.album}\u0000${t.albumArtist}", () => []).add(t);
    }
    final q = _q();
    final keys = groups.keys.where((k) => q.isEmpty || groups[k]!.any((t) => _matches(t, q))).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (keys.isEmpty) return _empty(themeColor, "NO ALBUMS");
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final tracks = groups[keys[i]]!;
        final first = tracks.first;
        return InkWell(
          onTap: () => setState(() => _detail = _Detail(first.album, _albumOrder(tracks), keepOrder: true)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (context, c) => _ArtThumb(uri: first.uri, color: themeColor, size: c.maxWidth))),
              const SizedBox(height: 6),
              Text(first.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text("${first.albumArtist}${first.year > 0 ? ' • ${first.year}' : ''}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }

  Widget _playlists(Color themeColor) {
    return ValueListenableBuilder<List<Playlist>>(
      valueListenable: PlaylistStore.playlists,
      builder: (context, lists, _) => ListView(
        children: [
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: themeColor),
            title: Text("NEW PLAYLIST", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
            onTap: () async {
              final name = await promptPlaylistName(context, themeColor);
              if (name != null && name.isNotEmpty) PlaylistStore.create(name);
            },
          ),
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
            title: const Text("FAVORITES", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
            subtitle: Text("${PlaylistStore.favorites.value.length} tracks", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
            onTap: () => setState(() => _detail = _playlistDetail('fav')),
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.cyanAccent),
            title: const Text("RECENTLY PLAYED", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
            subtitle: Text("${PlaylistStore.recent.value.length} tracks", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
            onTap: () => setState(() => _detail = _playlistDetail('recent')),
          ),
          for (final p in lists)
            ListTile(
              leading: Icon(Icons.queue_music, color: themeColor),
              title: Text(p.name, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
              subtitle: Text("${p.paths.length} tracks", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
              trailing: PopupMenuButton<String>(
                color: Colors.black,
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                onSelected: (v) async {
                  if (v == 'rename') {
                    final name = await promptPlaylistName(context, themeColor, initial: p.name, title: 'RENAME PLAYLIST');
                    if (name != null && name.isNotEmpty) PlaylistStore.rename(p.id, name);
                  } else if (v == 'delete') {
                    PlaylistStore.delete(p.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('RENAME', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white))),
                  PopupMenuItem(value: 'delete', child: Text('DELETE PLAYLIST', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent))),
                ],
              ),
              onTap: () => setState(() => _detail = _playlistDetail('user:${p.id}')),
            ),
        ],
      ),
    );
  }

  Widget _detailView(Color themeColor) {
    final d = _detail!;
    final q = _q();
    final list = d.keepOrder ? d.tracks.where((t) => _matches(t, q)).toList() : _sorted(d.tracks.where((t) => _matches(t, q)).toList());
    final userPlaylist = d.playlistId != null && d.playlistId!.startsWith('user:') && q.isEmpty;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              IconButton(icon: Icon(Icons.arrow_back, color: themeColor), onPressed: () => setState(() => _detail = null)),
              Expanded(child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor))),
            ],
          ),
        ),
        _playBar(list, themeColor),
        Expanded(
          child: list.isEmpty
              ? _empty(themeColor, "EMPTY")
              : userPlaylist
                  ? ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: list.length,
                      onReorderItem: (o, n) {
                        PlaylistStore.reorder(d.playlistId!.substring(5), o, n > o ? n + 1 : n);
                        _refreshPlaylistDetail();
                      },
                      itemBuilder: (context, i) => KeyedSubtree(
                        key: ValueKey('pl_${i}_${list[i].path}'),
                        child: _trackTile(list[i], list, i, themeColor,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.more_vert, color: Colors.white54), onPressed: () => _trackMenu(list[i], list, i, themeColor)),
                              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, color: Colors.white38))),
                            ])),
                      ),
                    )
                  : ListView.builder(itemCount: list.length, itemBuilder: (context, i) => _trackTile(list[i], list, i, themeColor)),
        ),
      ],
    );
  }

  Widget _empty(Color themeColor, String text) {
    return Center(child: Text(text, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor.withValues(alpha: 0.6))));
  }

  Widget _body(Color themeColor) {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: themeColor, size: 48),
              const SizedBox(height: 12),
              const Text("THE LIBRARY NEEDS PERMISSION TO READ YOUR MUSIC.", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => openAppSettings(), style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)), child: Text("OPEN APP SETTINGS", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor))),
              TextButton(onPressed: _scan, child: const Text("TRY AGAIN", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
            ],
          ),
        ),
      );
    }
    if (!_loadedOnce) {
      return Center(child: _loading ? CircularProgressIndicator(color: themeColor) : OutlinedButton(onPressed: _scan, style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)), child: Text("SCAN MUSIC LIBRARY", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor))));
    }
    if (_detail != null) return _detailView(themeColor);
    switch (_view) {
      case _View.songs:
        return _all.isEmpty ? _empty(themeColor, "NO MUSIC FOUND ON THIS DEVICE") : _songs(themeColor, _all);
      case _View.albums:
        return _albums(themeColor);
      case _View.artists:
        final groups = <String, List<LibTrack>>{};
        for (final t in _all) {
          groups.putIfAbsent(t.artist, () => []).add(t);
        }
        return _groupList(themeColor, groups, Icons.person, subtitle: (k, v) => "${v.map((t) => t.album).toSet().length} albums • ${v.length} tracks");
      case _View.folders:
        final groups = <String, List<LibTrack>>{};
        for (final t in _all) {
          groups.putIfAbsent(t.folder, () => []).add(t);
        }
        return _groupList(themeColor, groups, Icons.folder, folderMode: true, subtitle: (k, v) => "${v.length} tracks • $k");
      case _View.playlists:
        return _playlists(themeColor);
      case _View.recent:
        final recent = List<LibTrack>.from(_all)..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        final list = recent.take(150).where((t) => _matches(t, _q())).toList();
        return Column(
          children: [
            _playBar(list, themeColor),
            Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (context, i) => _trackTile(list[i], list, i, themeColor))),
          ],
        );
    }
  }

  String _viewLabel(_View v) => switch (v) {
        _View.songs => "SONGS",
        _View.albums => "ALBUMS",
        _View.artists => "ARTISTS",
        _View.folders => "FOLDERS",
        _View.playlists => "PLAYLISTS",
        _View.recent => "NEW",
      };

  String _sortLabel(_Sort s) => switch (s) {
        _Sort.title => "TITLE",
        _Sort.artist => "ARTIST",
        _Sort.album => "ALBUM",
        _Sort.added => "DATE ADDED",
        _Sort.duration => "LENGTH",
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return PopScope(
          canPop: _detail == null || SovereignState.currentTab.value != 4,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _detail != null) setState(() => _detail = null);
          },
          child: Container(
            color: Colors.black,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text("LIBRARY", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2))),
                      if (_status.isNotEmpty) Text(_status, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: _status.startsWith('ERR') ? Colors.redAccent : Colors.white38)),
                      PopupMenuButton<_Sort>(
                        tooltip: "SORT",
                        color: Colors.black,
                        icon: Icon(Icons.sort, color: themeColor),
                        onSelected: (s) => setState(() => _sort = s),
                        itemBuilder: (_) => [
                          for (final s in _Sort.values)
                            PopupMenuItem(value: s, child: Text(_sortLabel(s), style: TextStyle(fontFamily: 'ShareTechMono', color: s == _sort ? themeColor : Colors.white))),
                        ],
                      ),
                      IconButton(
                        tooltip: "RESCAN",
                        icon: _loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor)) : Icon(Icons.refresh, color: themeColor),
                        onPressed: _loading ? null : _scan,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
                    decoration: InputDecoration(
                      hintText: "SEARCH SONGS, ARTISTS, ALBUMS...",
                      hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: themeColor),
                      suffixIcon: _searchCtrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, color: Colors.white54), onPressed: _searchCtrl.clear),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.black,
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    children: [
                      for (final v in _View.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_viewLabel(v), style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: _view == v && _detail == null ? Colors.black : Colors.white70)),
                            selected: _view == v && _detail == null,
                            selectedColor: themeColor,
                            backgroundColor: Colors.black,
                            side: BorderSide(color: _view == v ? themeColor : Colors.white24),
                            showCheckmark: false,
                            onSelected: (_) => setState(() {
                              _view = v;
                              _detail = null;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(color: themeColor.withValues(alpha: 0.2), height: 1),
                Expanded(
                  child: RefreshIndicator(
                    color: themeColor,
                    backgroundColor: Colors.black,
                    onRefresh: () => _scan(silent: true),
                    child: _body(themeColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
