import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// A song carrying only what the grid's grouping reads: title/translit for the
/// name buckets and title order, version for the version folders, and the
/// singles/doubles levels for the level folders.
SongItem item({
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

  return SongItem(
    songInfo: SongInfo(
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
    ),
    isFav: false,
  );
}

List<String> titlesOf(ArcadeSection section) =>
    section.items.map((i) => i.songInfo.title).toList();

void main() {
  group('groupSongItems', () {
    test('title sort collects hiragana titles into one folder', () {
      // The hiragana bucket is "title contains Japanese", but the sort key is
      // the translit — so these songs are scattered through alphabetical order
      // and a run-length split of the sorted list would shard the folder.
      final sections = groupSongItems(
        <SongItem>[
          item(title: 'Afronova'),
          item(title: '愛', translit: 'ai'),
          item(title: 'Butterfly'),
          item(title: '桜', translit: 'sakura'),
          item(title: 'Trip Machine'),
        ],
        SortType.title,
        Modes.singles,
      );

      final hiragana =
          sections.firstWhere((s) => s.label == 'A (HIRAGANA)');
      expect(titlesOf(hiragana), <String>['愛', '桜']);
      // Hiragana leads the bucket order, ahead of the letter ranges.
      expect(sections.first.label, 'A (HIRAGANA)');
      expect(sections.map((s) => s.label).toList(),
          <String>['A (HIRAGANA)', 'A-C', 'S-U']);
    });

    test('version sort folders by exact release, newest first', () {
      final sections = groupSongItems(
        <SongItem>[
          item(title: 'Old', version: 'DDR'),
          item(title: 'New', version: 'DDR World'),
          item(title: 'Mid', version: 'DDR X2'),
        ],
        SortType.version,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['DDR WORLD', 'DDR X2', 'DDR']);
    });

    test('level sort folders by lowest charted level in the mode', () {
      final sections = groupSongItems(
        <SongItem>[
          item(title: 'Hard', singles: const <int?>[null, null, null, 15, 17]),
          item(title: 'Easy', singles: const <int?>[2, 4, null, null, null]),
          item(title: 'AlsoEasy', singles: const <int?>[2, 7, null, null, null]),
        ],
        SortType.level,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['LEVEL 2', 'LEVEL 15']);
      // Songs within a folder order by title.
      expect(titlesOf(sections.first), <String>['AlsoEasy', 'Easy']);
    });

    test('songs with no charts in the mode land in a trailing folder', () {
      final sections = groupSongItems(
        <SongItem>[
          item(
            title: 'SinglesOnly',
            singles: const <int?>[null, 5, null, null, null],
            doubles: const <int?>[null, null, null, null, null],
          ),
          item(
            title: 'BothModes',
            doubles: const <int?>[null, 6, null, null, null],
          ),
        ],
        SortType.level,
        Modes.doubles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['LEVEL 6', 'NO CHART']);
      expect(titlesOf(sections.last), <String>['SinglesOnly']);
    });

    test('an empty song list produces no folders', () {
      expect(
        groupSongItems(<SongItem>[], SortType.title, Modes.singles),
        isEmpty,
      );
    });
  });
}
