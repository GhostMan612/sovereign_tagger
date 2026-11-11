// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/storage_client.dart';
import 'main_shell.dart';
import 'photo_editor_screen.dart';

class PhotoItem {
  final int id;
  final String uri;
  final String path;
  final String displayName;
  final String mime;
  final int size;
  final int dateAdded;
  final int width;
  final int height;

  const PhotoItem({
    required this.id,
    required this.uri,
    required this.path,
    required this.displayName,
    required this.mime,
    required this.size,
    required this.dateAdded,
    required this.width,
    required this.height,
  });

  factory PhotoItem.fromMap(Map<String, Object?> m) => PhotoItem(
        id: (m['id'] as num?)?.toInt() ?? 0,
        uri: m['uri']?.toString() ?? '',
        path: m['path']?.toString() ?? '',
        displayName: m['displayName']?.toString() ?? '',
        mime: m['mime']?.toString() ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        dateAdded: (m['dateAdded'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
      );

  String get dimensions => width > 0 && height > 0 ? '${width}x$height' : '';

  String get dateLabel {
    if (dateAdded <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<PhotoItem> _photos = [];
  final Map<String, Uint8List?> _thumbs = {};
  bool _loading = true;
  bool _permissionDenied = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = 'Scanning photos...';
    });
    try {
      if (!await StorageClient.requestPhotosPermission()) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _permissionDenied = true;
          _status = 'Photo permission denied.';
        });
        return;
      }
      final rows = await StorageClient.queryPhotos();
      final photos = rows.map(PhotoItem.fromMap).where((p) => p.uri.isNotEmpty).toList();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
        _permissionDenied = false;
        _status = '${photos.length} photos';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'ERR: $e';
      });
    }
  }

  Future<Uint8List?> _thumbFor(PhotoItem photo) async {
    if (_thumbs.containsKey(photo.uri)) return _thumbs[photo.uri];
    final bytes = await StorageClient.loadPhotoThumbnail(photo.uri, size: 256);
    _thumbs[photo.uri] = bytes;
    return bytes;
  }

  void _openViewer(int index) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _PhotosViewerScreen(photos: _photos, initialIndex: index)),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = SovereignState.accentColor.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('PHOTOS', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        iconTheme: IconThemeData(color: themeColor),
        actions: [
          IconButton(
            tooltip: 'RESCAN',
            icon: _loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor)) : Icon(Icons.refresh, color: themeColor),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(themeColor),
    );
  }

  Widget _buildBody(Color themeColor) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: themeColor));
    }
    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)),
              child: Text('TRY AGAIN', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
            ),
          ],
        ),
      );
    }
    if (_photos.isEmpty) {
      return Center(child: Text('NO PHOTOS FOUND', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_status, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white38)),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              return GestureDetector(
                onTap: () => _openViewer(index),
                child: Container(
                  color: Colors.white10,
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbFor(photo),
                    builder: (context, snap) {
                      if (snap.data == null) {
                        return const Center(child: Icon(Icons.image_outlined, color: Colors.white24, size: 28));
                      }
                      return Image.memory(snap.data!, fit: BoxFit.cover);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PhotosViewerScreen extends StatefulWidget {
  final List<PhotoItem> photos;
  final int initialIndex;
  const _PhotosViewerScreen({required this.photos, required this.initialIndex});

  @override
  State<_PhotosViewerScreen> createState() => _PhotosViewerScreenState();
}

class _PhotosViewerScreenState extends State<_PhotosViewerScreen> {
  late final PageController _pageController;
  final Map<String, Uint8List> _fullBytes = {};
  int _index = 0;
  bool _zoomed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _fullFor(PhotoItem photo) async {
    if (_fullBytes.containsKey(photo.uri)) return _fullBytes[photo.uri];
    final bytes = await StorageClient.loadPhoto(photo.uri, maxSize: 2048);
    if (bytes != null) _fullBytes[photo.uri] = bytes;
    return bytes;
  }

  PhotoItem get _current => widget.photos[_index];

  Future<void> _shareCurrent() async {
    final ok = await StorageClient.sharePhoto(uri: _current.uri, mimeType: _current.mime.isNotEmpty ? _current.mime : 'image/jpeg');
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share failed', style: TextStyle(fontFamily: 'ShareTechMono'))));
    }
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() => _saving = true);
    final target = await StorageClient.exportPhotoToPictures(uri: _current.uri, displayName: _current.displayName);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(target == null ? 'Save failed' : 'Saved to $target', style: const TextStyle(fontFamily: 'ShareTechMono'))),
    );
  }

  Future<void> _openEditor() async {
    final bytes = await _fullFor(_current);
    if (bytes == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditorScreen(
          uri: _current.uri,
          path: _current.path,
          displayName: _current.displayName,
          mime: _current.mime,
          width: _current.width,
          height: _current.height,
          previewBytes: bytes,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = SovereignState.accentColor.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          _current.displayName,
          style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: IconThemeData(color: themeColor),
        actions: [
          IconButton(tooltip: 'EDIT', icon: Icon(Icons.edit, color: themeColor), onPressed: _openEditor),
          IconButton(tooltip: 'SHARE', icon: Icon(Icons.share, color: themeColor), onPressed: _shareCurrent),
          IconButton(
            tooltip: 'SAVE COPY',
            icon: _saving
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                : Icon(Icons.save_alt, color: themeColor),
            onPressed: _saving ? null : _saveCurrent,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: widget.photos.length,
              onPageChanged: (i) {
                if (!mounted) return;
                setState(() {
                  _index = i;
                  _zoomed = false;
                });
              },
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return _PhotoPage(
                  photo: photo,
                  loadFull: () => _fullFor(photo),
                  onZoomChanged: (zoomed) {
                    if (!mounted || index != _index) return;
                    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                  },
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black,
            child: Text(
              '${_index + 1} / ${widget.photos.length}   ${_current.dimensions}   ${PhotoItem.formatSize(_current.size)}   ${_current.dateLabel}',
              style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  final PhotoItem photo;
  final Future<Uint8List?> Function() loadFull;
  final ValueChanged<bool> onZoomChanged;
  const _PhotoPage({required this.photo, required this.loadFull, required this.onZoomChanged});

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final TransformationController _controller = TransformationController();
  late final Future<Uint8List?> _fullFuture = widget.loadFull();
  Offset _doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed) {
      _controller.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      _controller.value = Matrix4.identity()
        ..translateByDouble(-_doubleTapPosition.dx * (scale - 1), -_doubleTapPosition.dy * (scale - 1), 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0);
    }
    widget.onZoomChanged(!zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _fullFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Center(
            child: Text('COULD NOT LOAD PHOTO', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
          );
        }
        return GestureDetector(
          onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1.0,
            maxScale: 5.0,
            onInteractionEnd: (_) {
              widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
            },
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        );
      },
    );
  }
}
