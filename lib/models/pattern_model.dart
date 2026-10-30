/// Name: Pattern model + loader
/// Description: Each chart's pattern analysis ([analyseChart]) as stored in
/// assets/patterns/<name>.json by tool/generate_patterns.dart, ranked against
/// the other charts of its level (assets/pattern_levels.json). Read lazily
/// when a song page opens.
library;

import 'dart:convert';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter/material.dart';

const kPatternLabels = <Pattern, String>{
  Pattern.crossover: "Crossovers",
  Pattern.footswitch: "Footswitches",
  Pattern.sideswitch: "Side switches",
  Pattern.jack: "Jacks",
  Pattern.doublestep: "Doublesteps",
  Pattern.bracket: "Brackets",
  Pattern.candle: "Candles",
  Pattern.drill: "Drills",
  Pattern.staircase: "Staircases",
};

/// One glyph per pattern, shared by the song page and the chart preview.
const kPatternIcons = <Pattern, IconData>{
  Pattern.crossover: Icons.shuffle,
  Pattern.footswitch: Icons.swap_vert,
  Pattern.sideswitch: Icons.swap_horiz,
  Pattern.jack: Icons.repeat_one,
  Pattern.doublestep: Icons.double_arrow,
  Pattern.bracket: Icons.data_array,
  Pattern.candle: Icons.local_fire_department,
  Pattern.drill: Icons.multiple_stop,
  Pattern.staircase: Icons.stairs,
};

/// What a chart is known for, relative to its level. Balanced when nothing
/// leads; Signature (one uncommon pattern) only by the player's pick.
enum ChartCategory {
  stream,
  stamina,
  burst,
  jumps,
  jack,
  crossover,
  footswitch,
  bracket,
  swing,
  freeze,
  gimmick,
  signature,
  balanced,
}

const kCategoryLabels = <ChartCategory, String>{
  ChartCategory.stream: "Stream",
  ChartCategory.stamina: "Stamina",
  ChartCategory.burst: "Burst",
  ChartCategory.jumps: "Jumps",
  ChartCategory.jack: "Jack/trill",
  ChartCategory.crossover: "Crossover",
  ChartCategory.footswitch: "Footswitch",
  ChartCategory.bracket: "Bracket",
  ChartCategory.swing: "Swing",
  ChartCategory.freeze: "Freeze",
  ChartCategory.gimmick: "Gimmick",
  ChartCategory.signature: "Signature",
  ChartCategory.balanced: "Balanced",
};

const kCategoryIcons = <ChartCategory, IconData>{
  ChartCategory.stream: Icons.waves,
  ChartCategory.stamina: Icons.battery_charging_full,
  ChartCategory.burst: Icons.bolt,
  ChartCategory.jumps: Icons.unfold_more,
  ChartCategory.jack: Icons.repeat_one,
  ChartCategory.crossover: Icons.shuffle,
  ChartCategory.footswitch: Icons.swap_vert,
  ChartCategory.bracket: Icons.data_array,
  ChartCategory.swing: Icons.music_note,
  ChartCategory.freeze: Icons.ac_unit,
  ChartCategory.gimmick: Icons.speed,
  ChartCategory.signature: Icons.fingerprint,
  ChartCategory.balanced: Icons.balance,
};

/// The categories ranked against the level.
final kRankedCategories = [
  for (final c in ChartCategory.values)
    if (c != ChartCategory.balanced && c != ChartCategory.signature) c
];

/// A chart takes a category from this percentile of its level, and leads with
/// it when it is also this far clear of the next.
const kCategoryPercentile = 85;
const kCategoryLead = 5;
const kMaxSecondaryCategories = 2;

/// A pattern stands out when the chart has at least this many and does more
/// of it per step than this share of its level.
const kStandoutMinCount = 4;
const kStandoutPercentile = 80;

/// Format of assets/patterns/<name>.json and assets/pattern_levels.json. Bump
/// when either changes shape, so files in an older format are refused rather
/// than misread.
const kPatternsSchema = 3;

/// Rates are kept to this precision, so a chart ranks the same against the
/// stored table as it would against the exact values.
double _rounded(double v) => (v * 1000).roundToDouble() / 1000;

/// Share (0-100) of [cohort] strictly below [value], ties counting half.
int percentileOf(double value, Iterable<double> cohort) {
  var below = 0.0, n = 0;
  for (final v in cohort) {
    n++;
    if (v < value) {
      below += 1;
    } else if (v == value) {
      below += 0.5;
    }
  }
  return n == 0 ? 0 : (below * 100 / n).round();
}

class ChartPatterns {
  final int level;
  final int steps;
  final Map<Pattern, int> counts;

  /// Beat of each occurrence.
  final Map<Pattern, List<double>> at;
  final int fullCrossovers;
  final int upFootswitches;
  final int downFootswitches;
  final Map<String, int> rhythm;

  /// Per pattern name: the share, 0-100, of same-style
  /// charts within a level either side that do less of it per step.
  final Map<String, int> percentiles;

  /// [characterOf]'s measures, plus "gimmick": time off the main BPM and
  /// stops. Empty in files made before categories existed.
  final Map<String, double> character;

  /// Per [kRankedCategories] entry, ranked like [percentiles].
  final Map<ChartCategory, int> categoryPercentiles;

  const ChartPatterns({
    required this.level,
    required this.steps,
    required this.counts,
    required this.at,
    required this.fullCrossovers,
    required this.upFootswitches,
    required this.downFootswitches,
    required this.rhythm,
    this.percentiles = const {},
    this.character = const {},
    this.categoryPercentiles = const {},
  });

  factory ChartPatterns.fromAnalysis(ChartAnalysis a, int level,
          {double gimmick = 0}) =>
      ChartPatterns(
        level: level,
        steps: a.steps,
        counts: {for (final p in Pattern.values) p: a.footwork.count(p)},
        at: a.footwork.at,
        fullCrossovers: a.footwork.fullCrossovers,
        upFootswitches: a.footwork.upFootswitches,
        downFootswitches: a.footwork.downFootswitches,
        rhythm: a.rhythm,
        character: {
          for (final e in a.character.entries) e.key: _rounded(e.value),
          if (a.character.isNotEmpty) "gimmick": _rounded(gimmick),
        },
      );

  ChartPatterns withPercentiles(Map<String, int> percentiles,
          Map<ChartCategory, int> categoryPercentiles) =>
      ChartPatterns(
        level: level,
        steps: steps,
        counts: counts,
        at: at,
        fullCrossovers: fullCrossovers,
        upFootswitches: upFootswitches,
        downFootswitches: downFootswitches,
        rhythm: rhythm,
        percentiles: percentiles,
        character: character,
        categoryPercentiles: categoryPercentiles,
      );

  /// Occurrences per 100 steps, what [percentiles] rank.
  double rate(Pattern p) => steps == 0 ? 0 : _rounded(counts[p]! * 100 / steps);

  /// What [categoryPercentiles] rank, null without [character].
  double? categoryValue(ChartCategory c) {
    if (character.isEmpty) return null;
    final grid = rhythm.values.fold(0, (a, b) => a + b);
    return switch (c) {
      ChartCategory.stamina => steps.toDouble(),
      ChartCategory.jack => rate(Pattern.jack) + rate(Pattern.drill),
      ChartCategory.crossover => rate(Pattern.crossover),
      ChartCategory.footswitch =>
        rate(Pattern.footswitch) + rate(Pattern.sideswitch),
      ChartCategory.bracket => rate(Pattern.bracket),
      ChartCategory.swing => grid == 0
          ? 0
          : _rounded(1 -
              ((rhythm["4"] ?? 0) + (rhythm["8"] ?? 0) + (rhythm["16"] ?? 0)) /
                  grid),
      ChartCategory.balanced || ChartCategory.signature => null,
      _ => character[c.name],
    };
  }

  /// Top-ranked categories at or over [kCategoryPercentile], highest first.
  List<ChartCategory> get _strong => [
        for (final c in kRankedCategories)
          if ((categoryPercentiles[c] ?? 0) >= kCategoryPercentile) c
      ]..sort(
          (a, b) => categoryPercentiles[b]!.compareTo(categoryPercentiles[a]!));

  /// The category the chart leads with, Balanced when none is clear; null
  /// when the chart has no category ranks.
  ChartCategory? get primaryCategory {
    if (categoryPercentiles.isEmpty) return null;
    final ranked = kRankedCategories.toList()
      ..sort(
          (a, b) => categoryPercentiles[b]!.compareTo(categoryPercentiles[a]!));
    final top = categoryPercentiles[ranked[0]]!;
    return top >= kCategoryPercentile &&
            top - categoryPercentiles[ranked[1]]! >= kCategoryLead
        ? ranked[0]
        : ChartCategory.balanced;
  }

  /// Other strong categories after the primary one.
  List<ChartCategory> get secondaryCategories {
    final primary = primaryCategory;
    return [
      for (final c in _strong)
        if (c != primary) c
    ].take(kMaxSecondaryCategories).toList();
  }

  /// The patterns this chart is known for, most distinctive first.
  List<Pattern> get standouts => [
        for (final p in Pattern.values)
          if (counts[p]! >= kStandoutMinCount &&
              (percentiles[p.name] ?? 0) >= kStandoutPercentile)
            p
      ]..sort((a, b) => percentiles[b.name]!.compareTo(percentiles[a.name]!));

  factory ChartPatterns.fromJson(Map<String, dynamic> j) {
    final counts = j["counts"] as Map<String, dynamic>;
    final at = j["at"] as Map<String, dynamic>;
    return ChartPatterns(
      level: j["level"],
      steps: j["steps"],
      counts: {for (final p in Pattern.values) p: counts[p.name] ?? 0},
      at: {
        for (final p in Pattern.values)
          p: [for (final b in at[p.name] ?? []) (b as num).toDouble()]
      },
      fullCrossovers: j["full_crossovers"],
      upFootswitches: j["up_footswitches"],
      downFootswitches: j["down_footswitches"],
      rhythm: (j["rhythm"] as Map<String, dynamic>).cast<String, int>(),
      character: {
        for (final e in (j["character"] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as num).toDouble()
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "level": level,
      "steps": steps,
      "counts": {for (final e in counts.entries) e.key.name: e.value},
      "at": {
        for (final e in at.entries)
          if (e.value.isNotEmpty)
            e.key.name: [for (final b in e.value) _rounded(b)]
      },
      "full_crossovers": fullCrossovers,
      "up_footswitches": upFootswitches,
      "down_footswitches": downFootswitches,
      "rhythm": rhythm,
      if (character.isNotEmpty) "character": character,
    };
  }
}

/// All analysed charts of one song, keyed like [Difficulty.availableTypes].
class SongPatterns {
  final Map<String, ChartPatterns> singles;
  final Map<String, ChartPatterns> doubles;

  const SongPatterns({required this.singles, required this.doubles});

  static Map<String, ChartPatterns> _charts(dynamic j) =>
      (j as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, ChartPatterns.fromJson(v)));

  factory SongPatterns.fromJson(Map<String, dynamic> j) =>
      SongPatterns(singles: _charts(j["sp"]), doubles: _charts(j["dp"]));

  Map<String, dynamic> toJson() => {
        "schema": kPatternsSchema,
        "sp": singles.map((k, v) => MapEntry(k, v.toJson())),
        "dp": doubles.map((k, v) => MapEntry(k, v.toJson())),
      };

  ChartPatterns? chartFor(Modes mode, String difficultyKey) =>
      (mode == Modes.singles ? singles : doubles)[difficultyKey];
}

/// Every analysed chart's rate of each pattern, sorted, by style and level:
/// what [ChartPatterns.percentiles] rank against. One table rather than ranks
/// stored per song, so adding a song changes its own file and this one only.
class PatternLevels {
  final Map<Modes, Map<int, Map<Pattern, List<double>>>> rates;

  /// [ChartPatterns.categoryValue]s the same way, from charts that have them.
  final Map<Modes, Map<int, Map<ChartCategory, List<double>>>> categories;

  const PatternLevels(this.rates, [this.categories = const {}]);

  factory PatternLevels.of(Iterable<(Modes, ChartPatterns)> charts) {
    final rates = <Modes, Map<int, Map<Pattern, List<double>>>>{
      for (final m in Modes.values) m: {}
    };
    final categories = <Modes, Map<int, Map<ChartCategory, List<double>>>>{
      for (final m in Modes.values) m: {}
    };
    for (final (mode, c) in charts) {
      final byPattern = rates[mode]!
          .putIfAbsent(c.level, () => {for (final p in Pattern.values) p: []});
      for (final p in Pattern.values) {
        byPattern[p]!.add(c.rate(p));
      }
      if (c.character.isEmpty) continue;
      final byCategory = categories[mode]!.putIfAbsent(
          c.level, () => {for (final k in kRankedCategories) k: []});
      for (final k in kRankedCategories) {
        byCategory[k]!.add(c.categoryValue(k)!);
      }
    }
    for (final table in [rates, categories]) {
      for (final levels in table.values) {
        for (final byKey in levels.values) {
          for (final list in byKey.values) {
            list.sort();
          }
        }
      }
    }
    return PatternLevels(rates, categories);
  }

  /// [c] ranked against same-style charts within a level either side.
  ChartPatterns rank(Modes mode, ChartPatterns c) {
    final cohort = [
      for (int l = c.level - 1; l <= c.level + 1; l++)
        if (rates[mode]![l] case final byPattern?) byPattern
    ];
    final categoryCohort = [
      for (int l = c.level - 1; l <= c.level + 1; l++)
        if (categories[mode]?[l] case final byCategory?) byCategory
    ];
    return c.withPercentiles({
      for (final p in Pattern.values)
        p.name: percentileOf(c.rate(p), [for (final b in cohort) ...b[p]!]),
    }, {
      if (c.character.isNotEmpty && categoryCohort.isNotEmpty)
        for (final k in kRankedCategories)
          k: percentileOf(
              c.categoryValue(k)!, [for (final b in categoryCohort) ...b[k]!]),
    });
  }

  static String _key(Modes m) => m == Modes.singles ? "sp" : "dp";

  // Category lists sit under each level's "character" key, which apps from
  // before categories skip.
  factory PatternLevels.fromJson(Map<String, dynamic> j) => PatternLevels({
        for (final m in Modes.values)
          m: {
            for (final MapEntry(key: level, value: byPattern)
                in (j[_key(m)] as Map<String, dynamic>).entries)
              int.parse(level): {
                for (final p in Pattern.values)
                  p: [
                    for (final r in (byPattern as Map<String, dynamic>)[p.name])
                      (r as num).toDouble()
                  ]
              }
          }
      }, {
        for (final m in Modes.values)
          m: {
            for (final MapEntry(key: level, value: byPattern)
                in (j[_key(m)] as Map<String, dynamic>).entries)
              if ((byPattern as Map<String, dynamic>)["character"]
                  case final Map<String, dynamic> byCategory)
                int.parse(level): {
                  for (final k in kRankedCategories)
                    k: [
                      for (final r in byCategory[k.name] ?? [])
                        (r as num).toDouble()
                    ]
                }
          }
      });

  Map<String, dynamic> toJson() => {
        "schema": kPatternsSchema,
        for (final MapEntry(key: m, value: levels) in rates.entries)
          _key(m): {
            // Sorted, so the file is byte-identical whatever order charts
            // were analysed in (directory listing order differs by OS).
            for (final level in levels.keys.toList()..sort())
              "$level": {
                for (final e in levels[level]!.entries) e.key.name: e.value,
                if (categories[m]?[level] case final byCategory?)
                  "character": {
                    for (final e in byCategory.entries) e.key.name: e.value
                  },
              }
          }
      };
}

class PatternsLoader {
  /// Loaded with the first song and kept: it covers the whole library.
  static PatternLevels? _levels;
  static final _songs = <String, Future<SongPatterns?>>{};

  /// Drops the cached levels table and songs, after an update replaced them.
  static void reset() {
    _levels = null;
    _songs.clear();
  }

  /// [load], kept so the song list and its filter read each song once.
  static Future<SongPatterns?> cached(String songName) =>
      _songs.putIfAbsent(songName, () => load(songName));

  /// Null when the song has no analysis, so the page hides the section.
  static Future<SongPatterns?> load(String songName) async {
    final song = await _read("assets/patterns/$songName.json");
    if (song == null) return null;
    final levels =
        _levels ??= switch (await _read("assets/pattern_levels.json")) {
      final j? => PatternLevels.fromJson(j),
      null => null,
    };
    if (levels == null) return null;
    final raw = SongPatterns.fromJson(song);
    return SongPatterns(
      singles:
          raw.singles.map((k, c) => MapEntry(k, levels.rank(Modes.singles, c))),
      doubles:
          raw.doubles.map((k, c) => MapEntry(k, levels.rank(Modes.doubles, c))),
    );
  }

  static Future<Map<String, dynamic>?> _read(String path) async {
    final String raw;
    try {
      raw = await ContentStore.loadString(path);
    } catch (_) {
      return null;
    }
    final j = json.decode(raw);
    if (j is! Map<String, dynamic> || j["schema"] != kPatternsSchema) {
      debugPrint("$path is not schema $kPatternsSchema; "
          "rerun tool/generate_patterns.dart");
      return null;
    }
    return j;
  }
}
