/// Name: SongFilterTest
/// Description: The songlist's filter value type — how the three axes
/// combine when deciding whether a song is shown.
library;

import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// A song carrying only what filtering reads: title/translit for the name
/// buckets, version for the version buckets, and the per-mode levels.
SongInfo song({
  required String title,
  String? translit,
  String version = 'DDR World',
  List<int?> singles = const <int?>[null, 5, 8, 12, null],
  List<int?> doubles = const <int?>[null, 6, 9, 13, null],
}) {
  Difficulty diff(List<int?> levels) => Difficulty(
        beginner: levels[0],
        easy: levels[1],
        medium: levels[2],
        hard: levels[3],
        challenge: levels[4],
      );

  return SongInfo(
    ssc: false,
    version: version,
    name: title.toLowerCase(),
    title: title,
    titletranslit: translit ?? title,
    artist: 'artist',
    artisttranslit: 'artist',
    songLength: 100,
    perChart: false,
    singles: diff(singles),
    doubles: diff(doubles),
    radarSingles: const {},
    radarDoubles: const {},
    singlesNotecounts: diff(const <int?>[null, null, null, null, null]),
    doublesNotecounts: diff(const <int?>[null, null, null, null, null]),
    charts: const [],
  );
}

void main() {
  group('SongFilter.matches', () {
    final classic = song(title: 'Butterfly', version: '1st');
    final modern = song(title: 'Endymion', version: 'A20');

    test('an empty filter admits everything', () {
      const filter = SongFilter();
      expect(filter.matches(classic, Modes.singles), isTrue);
      expect(filter.matches(modern, Modes.singles), isTrue);
    });

    test('the axes intersect rather than union', () {
      // Level 12 matches both songs, but the version narrows it to one.
      const filter = SongFilter(
        levels: <int>{12},
        versionBuckets: <String>{'Classic (1st - X3)'},
      );
      expect(filter.matches(classic, Modes.singles), isTrue);
      expect(filter.matches(modern, Modes.singles), isFalse);
    });

    test('several levels on one axis union', () {
      final low = song(title: 'Low', singles: const <int?>[null, 3, null, null, null]);
      final high = song(title: 'High', singles: const <int?>[null, null, null, 17, null]);
      const filter = SongFilter(levels: <int>{3, 17});
      expect(filter.matches(low, Modes.singles), isTrue);
      expect(filter.matches(high, Modes.singles), isTrue);
    });

    test('level matching reads the selected mode', () {
      final s = song(
        title: 'Split',
        singles: const <int?>[null, 4, null, null, null],
        doubles: const <int?>[null, 9, null, null, null],
      );
      const filter = SongFilter(levels: <int>{4});
      expect(filter.matches(s, Modes.singles), isTrue);
      expect(filter.matches(s, Modes.doubles), isFalse);
    });

    test('favouritesOnly keeps only what the caller marks as a favourite', () {
      const filter = SongFilter(favouritesOnly: true);
      expect(filter.matches(classic, Modes.singles, isFav: true), isTrue);
      expect(filter.matches(classic, Modes.singles, isFav: false), isFalse);
    });
  });

  test('favouritesOnly alone counts as an active filter', () {
    // Drives whether the Clear button enables.
    expect(const SongFilter(favouritesOnly: true).isEmpty, isFalse);
  });

  // The song JSON carries bare version names ('WORLD', 'A20 PLUS'); matching
  // the 'DDR '-prefixed display form instead dropped every song into Classic.
  test('version buckets read the bare names the song data uses', () {
    expect(versionBucketFor('X3'), 'Classic (1st - X3)');
    expect(versionBucketFor('2013'), 'White (2013 - A)');
    expect(versionBucketFor('A20 PLUS'), 'Gold (A20 - World)');
    // The prefixed display form still resolves.
    expect(versionBucketFor('DDR World'), 'Gold (A20 - World)');
  });
}
