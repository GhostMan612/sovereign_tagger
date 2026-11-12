// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/sentinel_policy.dart';
import 'package:sovereign_tagger/core/title_cleaner.dart';

void main() {
  group('TitleCleaner buildSentinelFileName', () {
    test('formats standard track, album artist, and title with middle dot', () {
      final name = TitleCleaner.buildSentinelFileName(
        albumArtist: 'DMX',
        title: 'The Long Road',
        trackNo: '3',
        ext: 'flac',
      );
      expect(name, '03 - DMX · The Long Road.flac');
    });

    test('pads single digit track to 2 digits', () {
      final name = TitleCleaner.buildSentinelFileName(
        albumArtist: 'Metallica',
        title: 'Until It Sleeps',
        trackNo: '4',
        ext: 'mp3',
      );
      expect(name, '04 - Metallica · Until It Sleeps.mp3');
    });

    test('preserves 3-digit track numbers', () {
      final name = TitleCleaner.buildSentinelFileName(
        albumArtist: 'Various',
        title: 'Epic Track',
        trackNo: '105',
        ext: 'wav',
      );
      expect(name, '105 - Various · Epic Track.wav');
    });

    test('uses 00 placeholder when track is empty or unparseable', () {
      final name = TitleCleaner.buildSentinelFileName(
        albumArtist: 'Daft Punk',
        title: 'Aerodynamic',
        trackNo: '',
        ext: 'm4a',
      );
      expect(name, '00 - Daft Punk · Aerodynamic.m4a');
    });

    test('uses Untitled fallback when title and artist are missing', () {
      final name = TitleCleaner.buildSentinelFileName(
        albumArtist: '',
        title: '',
        trackNo: '',
        ext: 'opus',
      );
      expect(name, '00 - Untitled.opus');
    });
  });

  group('SentinelPolicy expectedFileName and Title Case', () {
    test('normalizes title casing with lowercase conjunctions', () {
      final expected = SentinelPolicy.expectedFileName({
        'TRACK': '1',
        'ALBUM_ARTIST': 'Queen',
        'TITLE': 'the show must go on',
      }, displayName: 'sample.flac');
      expect(expected, '01 - Queen · The Show Must Go On.flac');
    });

    test('preserves formal artist names verbatim and sanitizes filename chars', () {
      expect(SentinelPolicy.titleCase('ac/dc'), 'AC/DC');
      final expected = SentinelPolicy.expectedFileName({
        'TRACK': '2',
        'ALBUM_ARTIST': 'ac/dc',
        'TITLE': 'back in black',
      }, displayName: 'sample.mp3');
      expect(expected, '02 - ACDC · Back in Black.mp3');
    });

    test('canonicalizes feat to ft. in title', () {
      final expected = SentinelPolicy.expectedFileName({
        'TRACK': '5',
        'ALBUM_ARTIST': 'Eminem',
        'TITLE': 'stan (featuring dido)',
      }, displayName: 'sample.m4a');
      expect(expected, '05 - Eminem · Stan ft. Dido.m4a');
    });
  });
}
