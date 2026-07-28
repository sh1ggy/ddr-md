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
  int? bpm,
  List<int?> singles = const <int?>[null, 5, 8, 12, null],
  List<int?> doubles = const <int?>[null, 6, 9, 13, null],
  int? difficultyIndex,
  int? level,
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
      charts: bpm == null
          ? const []
          : <Chart>[
              Chart(
                dominantBpm: bpm,
                trueMin: bpm,
                trueMax: bpm,
                bpmRange: '$bpm',
                bpms: const [],
                stops: const [],
              ),
            ],
    ),
    isFav: false,
    difficultyIndex: difficultyIndex,
    level: level,
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
          item(title: 'Old', version: '1st'),
          item(title: 'New', version: 'WORLD'),
          item(title: 'Mid', version: 'X2'),
        ],
        SortType.version,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['WORLD', 'X2', '1ST']);
    });

    // A song-scoped row still falls back to the song's lowest level. The
    // songlist's level sort feeds chart-scoped rows (see chartItemsFor), so
    // this is the fallback path.
    test('a song-scoped row folders under the song lowest', () {
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

    test('a filter-scoped row folders under its chart, not the song lowest',
        () {
      // Filtering to 19 makes the row stand for the 19 chart, so a song whose
      // beginner is a 4 must not be dragged into LEVEL 4.
      final sections = groupSongItems(
        <SongItem>[
          item(
            title: 'Steps For Victory',
            singles: const <int?>[4, 8, 12, 16, 19],
            difficultyIndex: 4,
            level: 19,
          ),
        ],
        SortType.level,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(), <String>['LEVEL 19']);
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

    test('a song appears in every level folder it charts', () {
      // The regression: rows used to fold under the song's lowest chart, so a
      // boss song sat in LEVEL 4 and LEVEL 19 was all but empty.
      final song = item(
        title: 'Steps For Victory',
        singles: const <int?>[4, 8, 12, 16, 19],
      ).songInfo;

      final sections = groupSongItems(
        chartItemsFor(song, Modes.singles, isFav: false),
        SortType.level,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['LEVEL 4', 'LEVEL 8', 'LEVEL 12', 'LEVEL 16', 'LEVEL 19']);
      // Each row opens on the chart its folder stands for.
      expect(sections.last.items.single.difficultyIndex, 4);
    });

    test('an empty song list produces no folders', () {
      expect(
        groupSongItems(<SongItem>[], SortType.title, Modes.singles),
        isEmpty,
      );
    });

    test('bpm sort bands by tens, songs with no chart data last', () {
      final sections = groupSongItems(
        <SongItem>[
          item(title: 'Fast', bpm: 195),
          item(title: 'Slow', bpm: 140),
          item(title: 'Unknown'),
          item(title: 'AlsoSlow', bpm: 144),
        ],
        SortType.bpm,
        Modes.singles,
      );

      expect(sections.map((s) => s.label).toList(),
          <String>['NO BPM', 'BPM 140-149', 'BPM 190-199']);
      expect(titlesOf(sections[1]), <String>['AlsoSlow', 'Slow']);
    });

    test('descending reverses both the folders and their contents', () {
      final sections = groupSongItems(
        <SongItem>[
          item(title: 'Afronova'),
          item(title: 'Butterfly'),
          item(title: 'Trip Machine'),
        ],
        SortType.title,
        Modes.singles,
        descending: true,
      );

      expect(sections.map((s) => s.label).toList(), <String>['S-U', 'A-C']);
      expect(titlesOf(sections.last), <String>['Butterfly', 'Afronova']);
    });
  });

  group('chartItemsFor', () {
    test('a level filter keeps only the charts it selected', () {
      final song = item(
        title: 'Steps For Victory',
        singles: const <int?>[4, 8, 12, 16, 19],
      ).songInfo;

      final rows = chartItemsFor(song, Modes.singles,
          isFav: false, levels: const <int>{16, 19});

      expect(rows.map((r) => r.level).toList(), <int>[16, 19]);
    });

    test('a song with no chart in the mode yields one song-scoped row', () {
      final song = item(
        title: 'SinglesOnly',
        singles: const <int?>[null, 5, null, null, null],
        doubles: const <int?>[null, null, null, null, null],
      ).songInfo;

      final rows = chartItemsFor(song, Modes.doubles, isFav: false);

      expect(rows.single.isChartScoped, isFalse);
    });
  });
}
