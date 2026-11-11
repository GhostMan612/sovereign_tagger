// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';

import '../core/cloud_download.dart';
import '../core/cloud_pcloud.dart';
import '../core/cloud_settings.dart';
import '../core/cloud_source.dart';
import '../core/tap_feedback.dart';
import '../screens/main_shell.dart';
import '../screens/settings_screen.dart';

class CloudFolderView extends StatefulWidget {
  const CloudFolderView({super.key});

  @override
  State<CloudFolderView> createState() => _CloudFolderViewState();
}

class _CloudFolderViewState extends State<CloudFolderView> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<CloudEntry> _stack = <CloudEntry>[];
  List<CloudEntry> _entries = <CloudEntry>[];
  List<CloudEntry> _audio = <CloudEntry>[];
  bool _loading = false;
  String _error = '';
  String _query = '';
  String _downloadName = '';
  double _downloadProgress = 0;
  bool _downloading = false;
  bool _cancelDownload = false;

  CloudEntry get _current => _stack.isEmpty ? _rootEntry() : _stack.last;

  CloudEntry _rootEntry() {
    final path = CloudSettings.rootFolderPath;
    final name = path == '/' ? 'PCLOUD' : path.split('/').where((s) => s.isNotEmpty).last.toUpperCase();
    return CloudEntry(id: CloudSettings.rootFolderId.toString(), parentFolderId: '', name: name, path: path, isFolder: true);
  }

  @override
  void initState() {
    super.initState();
    _stack = <CloudEntry>[_rootEntry()];
    _load(_current);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(CloudEntry folder) async {
    if (!CloudSettings.hasToken) {
      setState(() {
        _entries = <CloudEntry>[];
        _audio = <CloudEntry>[];
        _error = 'NOT CONNECTED';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final entries = await PCloudProvider.instance.listFolder(folderId: folder.id, folderPath: folder.path);
      if (!mounted) return;
      setState(() {
        _entries = entries.where((e) => e.isFolder || e.isAudio).toList();
        _audio = entries.where((e) => !e.isFolder && e.isAudio).toList();
        _loading = false;
      });
    } on PCloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = <CloudEntry>[];
        _audio = <CloudEntry>[];
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = <CloudEntry>[];
        _audio = <CloudEntry>[];
        _error = 'PCLOUD DID NOT ANSWER — CHECK SIGNAL, THEN RETRY.';
        _loading = false;
      });
    }
  }

  List<CloudEntry> get _visible {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  void _enter(CloudEntry folder) {
    TapFeedback.machineTap();
    setState(() {
      _stack = <CloudEntry>[..._stack, folder];
      _query = '';
      _searchCtrl.clear();
    });
    _load(folder);
  }

  void _goTo(int index) {
    TapFeedback.machineTap();
    setState(() {
      _stack = _stack.sublist(0, index + 1);
      _query = '';
      _searchCtrl.clear();
    });
    _load(_current);
  }

  void _playAt(int index) {
    TapFeedback.machineTap();
    AudioService.playCloudEntries(_audio, startIndex: index);
  }

  void _playAll({bool shuffle = false}) {
    if (_audio.isEmpty) return;
    TapFeedback.machineTap();
    AudioService.playCloudEntries(_audio, shuffle: shuffle);
  }

  void _showEntryMenu(CloudEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(entry.name, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                subtitle: Text(entry.isFolder ? 'FOLDER' : _sizeLabel(entry.sizeBytes), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
              ),
              if (!entry.isFolder)
                ListTile(
                  leading: const Icon(Icons.play_arrow, color: Colors.cyanAccent),
                  title: const Text('PLAY NEXT', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    AudioService.addCloudEntriesToQueue(<CloudEntry>[entry], next: true);
                  },
                ),
              if (!entry.isFolder)
                ListTile(
                  leading: const Icon(Icons.queue_music, color: Colors.cyanAccent),
                  title: const Text('ADD TO QUEUE', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    AudioService.addCloudEntriesToQueue(<CloudEntry>[entry]);
                  },
                ),
              if (!entry.isFolder)
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.cyanAccent),
                  title: const Text('DOWNLOAD TO MUSIC', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadOne(entry);
                  },
                ),
              if (!entry.isFolder)
                ListTile(
                  leading: const Icon(Icons.offline_pin, color: Colors.cyanAccent),
                  title: const Text('DOWNLOAD FOR OFFLINE', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadOffline(entry);
                  },
                ),
              if (entry.isFolder)
                ListTile(
                  leading: const Icon(Icons.folder_download, color: Colors.cyanAccent),
                  title: const Text('DOWNLOAD FOLDER TO MUSIC', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadFolder(entry);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadOne(CloudEntry entry) async {
    setState(() {
      _downloading = true;
      _downloadName = entry.name;
      _downloadProgress = 0;
      _cancelDownload = false;
    });
    try {
      await CloudDownload.downloadEntry(
        entry,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total > 0 ? received / total : 0;
          });
        },
        isCancelled: () => _cancelDownload,
      );
      if (!mounted) return;
      _snack('${entry.name} SAVED TO MUSIC — TAGGABLE IN FORGE.');
    } on PCloudException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      _snack('DOWNLOAD FAILED — CHECK SIGNAL, THEN RETRY.');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadName = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _downloadOffline(CloudEntry entry) async {
    setState(() {
      _downloading = true;
      _downloadName = entry.name;
      _downloadProgress = 0;
      _cancelDownload = false;
    });
    try {
      await CloudDownload.downloadForOffline(
        entry,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total > 0 ? received / total : 0;
          });
        },
        isCancelled: () => _cancelDownload,
      );
      if (!mounted) return;
      _snack('${entry.name} CACHED FOR OFFLINE PLAY.');
    } on PCloudException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      _snack('DOWNLOAD FAILED — CHECK SIGNAL, THEN RETRY.');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadName = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _downloadFolder(CloudEntry folder) async {
    setState(() {
      _downloading = true;
      _downloadName = folder.name;
      _downloadProgress = 0;
      _cancelDownload = false;
    });
    try {
      final summary = await CloudDownload.downloadFolder(
        folder,
        onFile: (name, done, total) {
          if (!mounted) return;
          setState(() {
            _downloadName = name.isEmpty ? folder.name : name;
            _downloadProgress = total > 0 ? done / total : 0;
          });
        },
        isCancelled: () => _cancelDownload,
      );
      if (!mounted) return;
      _snack('FOLDER DONE — ${summary.succeeded} SAVED, ${summary.failed} FAILED${summary.cancelled ? ', CANCELLED' : ''}.');
    } on PCloudException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      _snack('FOLDER DOWNLOAD FAILED — CHECK SIGNAL, THEN RETRY.');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadName = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.cyanAccent))));
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final connected = CloudSettings.hasToken;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              const Icon(Icons.cloud, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (var i = 0; i < _stack.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (i > 0) const Text(' / ', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38)),
                            GestureDetector(
                              onTap: () => _goTo(i),
                              child: Text(
                                _stack[i].name,
                                style: TextStyle(fontFamily: 'ShareTechMono', color: i == _stack.length - 1 ? Colors.cyanAccent : Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 20),
                onPressed: () => _load(_current),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        if (!CloudSettings.dataWarned && connected)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('STREAMING USES MOBILE DATA. DOWNLOAD TO MUSIC ON WI-FI TO PLAY OFFLINE.', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amber, fontSize: 11)),
                ),
                TextButton(
                  onPressed: () {
                    CloudSettings.markDataWarned();
                    setState(() {});
                  },
                  child: const Text('GOT IT', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amber)),
                ),
              ],
            ),
          ),
        if (_downloading)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_downloadName, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null, color: Colors.cyanAccent, backgroundColor: Colors.white12),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _cancelDownload = true),
                  child: const Text('CANCEL', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'SEARCH THIS FOLDER',
                    hintStyle: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: Colors.cyanAccent, size: 18),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _audio.isEmpty ? null : () => _playAll(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                child: const Text('PLAY ALL', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _audio.isEmpty ? null : () => _playAll(shuffle: true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.cyanAccent, side: const BorderSide(color: Colors.cyanAccent)),
                child: const Text('SHUFFLE', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12)),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<String>(
          valueListenable: AudioService.cloudStatus,
          builder: (context, status, _) {
            if (status.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Text(status, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.amber, fontSize: 11)),
            );
          },
        ),
        Expanded(
          child: _buildBody(connected),
        ),
      ],
    );
  }

  Widget _buildBody(bool connected) {
    if (!connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              const Text('PCLOUD IS NOT CONNECTED.', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13)),
              const SizedBox(height: 6),
              const Text('CONNECT IN SETTINGS — YOU NEED A PCLOUD OAUTH APP FIRST.', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                child: const Text('OPEN SETTINGS', style: TextStyle(fontFamily: 'ShareTechMono')),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.signal_wifi_off, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _load(_current),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                child: const Text('RETRY', style: TextStyle(fontFamily: 'ShareTechMono')),
              ),
            ],
          ),
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return const Center(child: Text('NOTHING HERE — NO AUDIO IN THIS FOLDER.', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 12)));
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final entry = visible[index];
        if (entry.isFolder) {
          return ListTile(
            leading: const Icon(Icons.folder, color: Colors.cyanAccent),
            title: Text(entry.name, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _enter(entry),
            onLongPress: () => _showEntryMenu(entry),
          );
        }
        final audioIndex = _audio.indexWhere((e) => e.id == entry.id);
        return ListTile(
          leading: const Icon(Icons.cloud, color: Colors.cyanAccent, size: 20),
          title: Text(CloudDownload.displayName(entry.name), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('CLOUD · ${_sizeLabel(entry.sizeBytes)}', style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
          trailing: const Icon(Icons.play_arrow, color: Colors.white38),
          onTap: () => _playAt(audioIndex < 0 ? 0 : audioIndex),
          onLongPress: () => _showEntryMenu(entry),
        );
      },
    );
  }
}
