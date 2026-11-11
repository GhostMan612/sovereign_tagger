// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovereign_tagger/core/cloud_source.dart';
import 'package:sovereign_tagger/core/ghost_memory.dart';
import 'package:sovereign_tagger/services/sentinel_store.dart';

void main() {
  test('pCloud regions accept only canonical API hosts', () {
    expect(CloudRegion.fromHost(' API.PCLOUD.COM '), CloudRegion.us);
    expect(CloudRegion.fromHost('eapi.pcloud.com'), CloudRegion.eu);
    expect(
      () => CloudRegion.fromHost('eapi.pcloud.com.attacker.test'),
      throwsArgumentError,
    );
    expect(() => CloudRegion.fromHost('localhost'), throwsArgumentError);
  });

  test('Sentinel naming policy preserves extension and identifies missing tags', () {
    const tags = SentinelTagSnapshot(
      title: 'The Long Road',
      artist: 'DMX',
      albumArtist: 'DMX',
      album: 'Example Album',
      track: '3/12',
      year: '2022',
      genre: 'Hip-Hop',
      lyrics: 'Sample lyrics',
      artwork: true,
    );
    expect(
      SentinelNamingPolicy.formatExpectedFilename(
        tags: tags,
        currentFilename: 'old.flac',
      ),
      '03 - DMX · The Long Road.flac',
    );
    expect(
      SentinelNamingPolicy.evaluateIssues(
        tags: tags,
        displayName: '03 - DMX · The Long Road.flac',
      ),
      isEmpty,
    );
    expect(
      SentinelNamingPolicy.evaluateIssues(
        tags: const SentinelTagSnapshot(),
        displayName: 'unknown.mp3',
      ),
      contains(SentinelIssue.missingArtwork),
    );
  });

  test('Sentinel hit roundtrip retains evidence and issue state', () {
    const hit = SentinelHit(
      id: 'test-hit',
      uri: 'content://sample/1',
      path: '/sample/song.mp3',
      size: 42,
      dateAdded: 12,
      displayName: 'song.mp3',
      expectedName: '01 - Example - Song.mp3',
      issues: <String>[SentinelIssue.missingLyrics],
      severity: 'medium',
      tagSnapshot: SentinelTagSnapshot(title: 'Song', artist: 'Example'),
      evidence: <String, dynamic>{'sampled': false},
      status: SentinelStatus.open,
      firstSeen: '2026-01-01T00:00:00Z',
      lastSeen: '2026-01-01T00:00:00Z',
      scanId: 'example-scan',
    );
    final reloaded = SentinelHit.fromJson(hit.toJson());
    expect(reloaded.id, hit.id);
    expect(reloaded.issues, hit.issues);
    expect(reloaded.tagSnapshot.title, 'Song');
    expect(reloaded.evidence['sampled'], false);
  });

  test('Ghost memory serializes concurrent play records and can forget', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GhostMemory.forgetAll();
    await Future.wait(<Future<void>>[
      GhostMemory.recordPlay(path: '/example/1.mp3', title: 'One', artist: 'Example'),
      GhostMemory.recordPlay(path: '/example/2.mp3', title: 'Two', artist: 'Example'),
    ]);
    expect(GhostMemory.history.length, 2);
    expect(GhostMemory.artistCounts['Example'], 2);
    await GhostMemory.forgetAll();
    expect(GhostMemory.history, isEmpty);
    expect(GhostMemory.artistCounts, isEmpty);
  });
}
