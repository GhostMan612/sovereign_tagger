// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/dart_spider.dart';

void main() {
  group('DartSpider cleanTitle', () {
    test('removes bracket noise and official video tags', () {
      expect(DartSpider.cleanTitle('In The End (Official Music Video)'), 'In The End');
      expect(DartSpider.cleanTitle('Numb [Official Video]'), 'Numb');
      expect(DartSpider.cleanTitle('Crawling {Official Audio}'), 'Crawling');
      expect(DartSpider.cleanTitle('Faint (HD 4K Visualizer)'), 'Faint');
    });

    test('removes trailing noise after dashes or pipes', () {
      expect(DartSpider.cleanTitle('Papercut - Official Audio'), 'Papercut');
      expect(DartSpider.cleanTitle('Points of Authority | Lyric Video'), 'Points of Authority');
    });

    test('removes pipe tail suffix', () {
      expect(DartSpider.cleanTitle('Breaking The Habit | Official Clip'), 'Breaking The Habit');
    });

    test('collapses multiple whitespace', () {
      expect(DartSpider.cleanTitle('Somewhere   I    Belong'), 'Somewhere I Belong');
    });
  });

  group('DartSpider cleanArtist', () {
    test('removes topic and official suffixes', () {
      expect(DartSpider.cleanArtist('Linkin Park - Topic'), 'Linkin Park');
      expect(DartSpider.cleanArtist('Metallica VEVO'), 'Metallica');
      expect(DartSpider.cleanArtist('Coldplay (Official)'), 'Coldplay');
    });

    test('preserves diacritics in artist name while cleaning channel suffix', () {
      expect(DartSpider.cleanArtist('Mötley Crüe - Topic'), 'Mötley Crüe');
      expect(DartSpider.cleanArtist('Beyoncé VEVO'), 'Beyoncé');
      expect(DartSpider.cleanArtist('Sigur Rós (Official)'), 'Sigur Rós');
    });
  });
}
