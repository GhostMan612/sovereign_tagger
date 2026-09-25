// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import '../core/playlists.dart';

Future<String?> promptPlaylistName(BuildContext context, Color themeColor, {String initial = '', String title = 'NEW PLAYLIST'}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: themeColor)),
      title: Text(title, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.4))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
        ),
        onSubmitted: (v) => Navigator.pop(d, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('CANCEL', style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(d, ctrl.text.trim()),
          child: const Text('OK', style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

Future<void> showPlaylistPicker(BuildContext context, List<String> paths, Color themeColor, {bool createOnly = false}) async {
  if (paths.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String msg) => messenger?.showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'ShareTechMono'))));

  if (createOnly || PlaylistStore.playlists.value.isEmpty) {
    final name = await promptPlaylistName(context, themeColor);
    if (name == null || name.isEmpty) return;
    PlaylistStore.create(name, paths);
    toast('> SAVED ${paths.length} TRACK(S) TO "$name"');
    return;
  }

  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.black.withValues(alpha: 0.97),
    shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: themeColor.withValues(alpha: 0.5))),
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('ADD ${paths.length} TRACK(S) TO…', style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: themeColor)),
            ),
            ListTile(
              leading: Icon(Icons.add, color: themeColor),
              title: Text('NEW PLAYLIST', style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(sheet, '__new__'),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in PlaylistStore.playlists.value)
                    ListTile(
                      leading: const Icon(Icons.queue_music, color: Colors.white54),
                      title: Text(p.name, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      subtitle: Text('${p.paths.length} tracks', style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                      onTap: () => Navigator.pop(sheet, p.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == '__new__') {
    final name = await promptPlaylistName(context, themeColor);
    if (name == null || name.isEmpty) return;
    PlaylistStore.create(name, paths);
    toast('> SAVED ${paths.length} TRACK(S) TO "$name"');
    return;
  }
  PlaylistStore.addTo(choice, paths);
  final name = PlaylistStore.playlists.value.firstWhere((p) => p.id == choice, orElse: () => Playlist(id: '', name: 'playlist', paths: [], created: 0)).name;
  toast('> ADDED TO "$name"');
}
