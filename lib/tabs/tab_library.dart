// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../screens/main_shell.dart';

class TabLibrary extends StatefulWidget {
  const TabLibrary({super.key});

  @override
  State<TabLibrary> createState() => _TabLibraryState();
}

class _TabLibraryState extends State<TabLibrary> with AutomaticKeepAliveClientMixin {
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');

  String _statusMessage = "System Idle. Scanning MediaStore...";
  bool _isScanning = false;
  String _browseMode = "ALBUM"; // ALBUM, ARTIST, FOLDER
  
  List<MediaItem> _mediaItems = [];
  List<MediaItem> _filteredItems = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanMediaStore() async {
    setState(() { _isScanning = true; _statusMessage = "Scanning MediaStore..."; });
    try {
      // In a real implementation, this would query MediaStore via a method channel
      // For now, we'll use file picker to simulate
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus'],
        allowMultiple: true,
      );
      
      if (result != null) {
        final items = <MediaItem>[];
        for (final file in result.files) {
          if (file.path != null) {
            final tags = await _readTags(file.path!);
            items.add(MediaItem(
              path: file.path!,
              title: tags['TITLE'] ?? file.name,
              artist: tags['ARTIST'] ?? 'Unknown Artist',
              album: tags['ALBUM'] ?? 'Unknown Album',
              year: tags['YEAR'] ?? '',
              genre: tags['GENRE'] ?? '',
              trackNo: tags['TRACK'] ?? '',
              artworkBase64: tags['ARTWORK_BASE64'] ?? '',
            ));
          }
        }
        setState(() {
          _mediaItems = items;
          _filteredItems = items;
          _isScanning = false;
          _statusMessage = "Library Loaded: ${items.length} tracks";
        });
      } else {
        setState(() {
          _isScanning = false;
          _statusMessage = "No media selected. Tap SCAN to browse MediaStore.";
        });
      }
    } catch (e) {
      setState(() { _isScanning = false; _statusMessage = "ERR: Scan Fault: $e"; });
    }
  }

  Future<Map<String, String>> _readTags(String path) async {
    try {
      return await _storageChannel.invokeMethod('readTags', {'filePath': path}) ?? {};
    } catch (_) {
      return {};
    }
  }

  void _filterItems() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _mediaItems;
      } else {
        _filteredItems = _mediaItems.where((item) =>
          item.title.toLowerCase().contains(query) ||
          item.artist.toLowerCase().contains(query) ||
          item.album.toLowerCase().contains(query)
        ).toList();
      }
    });
  }

  void _playItem(MediaItem item, int index) {
    final files = _filteredItems.map((m) => File(m.path)).toList();
    AudioService.replacePlaylist(files, startIndex: index);
    AudioService.player.play();
    SovereignState.currentTab.value = 4; // Switch to Player tab
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border(bottom: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          "MEDIA LIBRARY",
                          style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2),
                        ),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _browseMode,
                          dropdownColor: Colors.black,
                          underline: Container(),
                          style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 14),
                          items: ["ALBUM", "ARTIST", "FOLDER"].map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)))).toList(),
                          onChanged: (v) => setState(() => _browseMode = v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
                      decoration: InputDecoration(
                        hintText: "SEARCH LIBRARY...",
                        hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38),
                        prefixIcon: Icon(Icons.search, color: themeColor),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanning ? null : _scanMediaStore,
                            icon: _isScanning
                                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                                : Icon(Icons.refresh, color: themeColor, size: 18),
                            label: Text(_isScanning ? "SCANNING..." : "SCAN MEDIASTORE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: themeColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Status
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border(bottom: BorderSide(color: _statusMessage.contains("ERR") ? Colors.redAccent : themeColor)),
                ),
                child: Text(
                  "> $_statusMessage",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'VT323',
                    fontSize: 14,
                    color: _statusMessage.contains("ERR") ? Colors.redAccent : themeColor,
                  ),
                ),
              ),

              // Library List
              Expanded(
                child: _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.library_music, size: 64, color: Colors.white24),
                            const SizedBox(height: 16),
                            Text(
                              "LIBRARY EMPTY",
                              style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 18, fontWeight: FontWeight.bold, color: themeColor),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Tap SCAN MEDIASTORE to populate",
                              style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          return _buildMediaTile(item, index, themeColor);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMediaTile(MediaItem item, int index, Color themeColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: themeColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
        leading: item.artworkBase64.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  base64Decode(item.artworkBase64),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.music_note, color: themeColor),
              ),
        title: Text(
          item.title,
          style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.artist,
              style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "${item.album}${item.year.isNotEmpty ? ' • ${item.year}' : ''}",
              style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Icon(Icons.play_circle_outline, color: themeColor),
        onTap: () => _playItem(item, index),
        ),
      ),
    );
  }
}

class MediaItem {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String year;
  final String genre;
  final String trackNo;
  final String artworkBase64;

  MediaItem({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.genre,
    required this.trackNo,
    required this.artworkBase64,
  });
}