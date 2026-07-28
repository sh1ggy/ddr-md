/// Name: song_sections
/// Parent: ArcadeGridView, DifficultyListPage
/// Description: Bucketing helpers shared by the songlist filters and the
/// arcade grid's folder banners, plus the grouping that turns a flat sorted
/// song list into the grid's sections.
library;

import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/helpers.dart';

// Name buckets in the order the filter tray and the grid's folders present
// them: Japanese titles first, then non-alphabetic, then the letter ranges.
const List<String> kNameBuckets = <String>[
  'a (hiragana)',
  '#',
  'a-c',
  'd-f',
  'g-i',
  'j-l',
  'm-o',
  'p-r',
  's-u',
  'v-z',
];

// Coarse era buckets used by the version filter chips.
const List<String> kVersionBuckets = <String>[
  'Classic (1st - X3)',
  'White (2013 - A)',
  'Gold (A20 - World)',
];

/// Every level this song charts in the given mode, deduplicated and limited to
/// the levels the app displays (1..maxDifficulty).
List<int> songLevels(SongInfo song, Modes mode) {
  final Difficulty songDifficulty =
      mode == Modes.singles ? song.singles : song.doubles;
  return <int?>[
    songDifficulty.beginner,
    songDifficulty.easy,
    songDifficulty.medium,
    songDifficulty.hard,
    songDifficulty.challenge,
  ]
      .whereType<int>()
      .where((level) => level >= 1 && level <= constants.maxDifficulty)
      .toSet()
      .toList();
}

/// The level a song sorts and folders under: its lowest charted level in the
/// mode. Songs with no charts in the mode sort last, past every real level.
int primaryLevelFor(SongInfo song, Modes mode) {
  final levels = songLevels(song, mode);
  if (levels.isEmpty) return constants.maxDifficulty + 1;
  levels.sort();
  return levels.first;
}

/// The level a row folders and sorts under. A chart-scoped row uses the chart
/// it stands for; only a song-scoped row falls back to the song's lowest.
int levelForItem(SongItem item, Modes mode) =>
    item.level ?? primaryLevelFor(item.songInfo, mode);

/// [song] as one row per chart it has in [mode], for the level sort — a song
/// charting both 3 and 19 belongs in LEVEL 3 *and* LEVEL 19, which is what the
/// cabinet's level folders list. Folding it under a single level would hide it
/// from the folder someone went looking in. [levels], when non-empty, keeps
/// only the charts the level filter selected.
///
/// A song with no chart in the mode yields one song-scoped row, so it still
/// appears once under NO CHART.
List<SongItem> chartItemsFor(
  SongInfo song,
  Modes mode, {
  required bool isFav,
  Set<int> levels = const <int>{},
}) {
  final Difficulty difficulty =
      mode == Modes.singles ? song.singles : song.doubles;
  final charts = difficulty.chartsByIndex
      .where((c) => c.level >= 1 && c.level <= constants.maxDifficulty)
      .where((c) => levels.isEmpty || levels.contains(c.level))
      .toList();
  if (charts.isEmpty) {
    return <SongItem>[SongItem(songInfo: song, isFav: isFav)];
  }
  return <SongItem>[
    for (final chart in charts)
      SongItem(
        songInfo: song,
        isFav: isFav,
        difficultyIndex: chart.index,
        level: chart.level,
      ),
  ];
}

String versionBucketFor(String version) {
  const white = <String>{'2013', '2014', 'A'};
  const gold = <String>{'A20', 'A20 PLUS', 'A3', 'WORLD'};

  final String key = constants.canonicalVersion(version);
  if (white.contains(key)) return 'White (2013 - A)';
  if (gold.contains(key)) return 'Gold (A20 - World)';
  return 'Classic (1st - X3)';
}

String nameBucketFor(SongInfo song) {
  final String title = song.title.trim();
  // Treat this bucket as "contains Japanese" anywhere in title.
  if (title.isNotEmpty &&
      RegExp(r'[぀-ヿ一-鿿ｦ-ﾟ]').hasMatch(title)) {
    return 'a (hiragana)';
  }

  final String key =
      (song.titletranslit.isNotEmpty ? song.titletranslit : song.title)
          .trim()
          .toLowerCase();
  if (key.isEmpty) return '#';

  final String first = key[0];
  if (!RegExp(r'[a-z]').hasMatch(first)) return '#';
  if ('abc'.contains(first)) return 'a-c';
  if ('def'.contains(first)) return 'd-f';
  if ('ghi'.contains(first)) return 'g-i';
  if ('jkl'.contains(first)) return 'j-l';
  if ('mno'.contains(first)) return 'm-o';
  if ('pqr'.contains(first)) return 'p-r';
  if ('stu'.contains(first)) return 's-u';
  return 'v-z';
}

/// The songlist's filter state: the three independent axes, as sets.
///
/// Kept as a value type apart from the page so option counts can be computed
/// against a hypothetical selection without touching widget state.
class SongFilter {
  const SongFilter({
    this.levels = const <int>{},
    this.versionBuckets = const <String>{},
    this.nameBucket,
    this.favouritesOnly = false,
  });

  final Set<int> levels;
  final Set<String> versionBuckets;
  // Single-select, unlike the other two: a song sits in exactly one name
  // bucket, so picking a second could only ever narrow to nothing.
  final String? nameBucket;
  final bool favouritesOnly;

  bool get isEmpty =>
      levels.isEmpty &&
      versionBuckets.isEmpty &&
      nameBucket == null &&
      !favouritesOnly;

  /// Whether [song] passes every axis. [isFav] comes from the caller because
  /// favourite state lives in the database, not on [SongInfo].
  bool matches(SongInfo song, Modes mode, {bool isFav = false}) {
    final bool levelMatch = levels.isEmpty ||
        songLevels(song, mode).any((int level) => levels.contains(level));
    final bool versionMatch = versionBuckets.isEmpty ||
        versionBuckets.contains(versionBucketFor(song.version));
    final bool nameMatch = nameBucket == null || nameBucket == nameBucketFor(song);
    final bool favMatch = !favouritesOnly || isFav;
    return levelMatch && versionMatch && nameMatch && favMatch;
  }
}

enum SongFilterAxis { name, level, version }

/// One folder of the arcade grid: a banner label plus the songs under it.
class ArcadeSection {
  const ArcadeSection({required this.label, required this.items});

  final String label;
  final List<SongItem> items;
}

/// Groups an already-filtered song list into the grid's folders for [sortType].
///
/// This is a real group-by rather than a run-length split of the sorted list:
/// the name buckets don't line up with the sorted order (a title sorts on its
/// translit, but any title containing Japanese buckets under hiragana), so
/// splitting where the key changes would scatter one folder across many.
/// Section order is canonical per sort, and items inside a section are ordered
/// by title.
List<ArcadeSection> groupSongItems(
  List<SongItem> items,
  SortType sortType,
  Modes mode, {
  bool descending = false,
}) {
  if (items.isEmpty) return const <ArcadeSection>[];
  final List<ArcadeSection> sections =
      _groupAscending(items, sortType, mode);
  if (!descending) return sections;
  // Reversed at both levels so the folders and their contents agree.
  return <ArcadeSection>[
    for (final section in sections.reversed)
      ArcadeSection(
        label: section.label,
        items: section.items.reversed.toList(),
      ),
  ];
}

List<ArcadeSection> _groupAscending(
  List<SongItem> items,
  SortType sortType,
  Modes mode,
) {
  switch (sortType) {
    case SortType.level:
      final Map<int, List<SongItem>> byLevel = <int, List<SongItem>>{};
      for (final item in items) {
        byLevel
            .putIfAbsent(levelForItem(item, mode), () => <SongItem>[])
            .add(item);
      }
      final levels = byLevel.keys.toList()..sort();
      return <ArcadeSection>[
        for (final level in levels)
          ArcadeSection(
            // Past the real levels sits the "no chart in this mode" folder
            // (e.g. a singles-only song while doubles is selected).
            label: level > constants.maxDifficulty
                ? 'NO CHART'
                : 'LEVEL $level',
            items: _byTitle(byLevel[level]!),
          ),
      ];

    case SortType.title:
      final Map<String, List<SongItem>> byName = <String, List<SongItem>>{};
      for (final item in items) {
        byName
            .putIfAbsent(nameBucketFor(item.songInfo), () => <SongItem>[])
            .add(item);
      }
      return <ArcadeSection>[
        for (final bucket in kNameBuckets)
          if (byName.containsKey(bucket))
            ArcadeSection(
              label: bucket.toUpperCase(),
              items: _byTitle(byName[bucket]!),
            ),
      ];

    case SortType.version:
      // Folders per exact release rather than the coarse filter buckets — the
      // cabinet's version folders are per release too.
      final Map<String, List<SongItem>> byVersion = <String, List<SongItem>>{};
      for (final item in items) {
        byVersion
            .putIfAbsent(item.songInfo.version, () => <SongItem>[])
            .add(item);
      }
      final versions = byVersion.keys.toList()
        ..sort((a, b) {
          final byIndex = versionIndex(a).compareTo(versionIndex(b));
          return byIndex != 0 ? byIndex : a.compareTo(b);
        });
      return <ArcadeSection>[
        for (final version in versions)
          ArcadeSection(
            label: version.toUpperCase(),
            items: _byTitle(byVersion[version]!),
          ),
      ];

    case SortType.bpm:
      // BPM has no natural folder boundaries, so it bands by tens.
      final Map<int, List<SongItem>> byBand = <int, List<SongItem>>{};
      for (final item in items) {
        byBand
            .putIfAbsent((bpmKey(item.songInfo) ~/ 10) * 10, () => <SongItem>[])
            .add(item);
      }
      final bands = byBand.keys.toList()..sort();
      return <ArcadeSection>[
        for (final band in bands)
          ArcadeSection(
            label: band == 0 ? 'NO BPM' : 'BPM $band-${band + 9}',
            items: _byTitle(byBand[band]!),
          ),
      ];
  }
}

// Sorts a folder's songs by title. The lists come from the maps built above,
// so sorting in place is safe — nothing else holds them.
List<SongItem> _byTitle(List<SongItem> items) {
  items.sort((a, b) => compareSongInfo(a.songInfo, b.songInfo, SortType.title));
  return items;
}
