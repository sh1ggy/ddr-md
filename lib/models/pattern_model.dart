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
  });

  factory ChartPatterns.fromAnalysis(ChartAnalysis a, int level) =>
      ChartPatterns(
        level: level,
        steps: a.steps,
        counts: {for (final p in Pattern.values) p: a.footwork.count(p)},
        at: a.footwork.at,
        fullCrossovers: a.footwork.fullCrossovers,
        upFootswitches: a.footwork.upFootswitches,
        downFootswitches: a.footwork.downFootswitches,
        rhythm: a.rhythm,
      );

  ChartPatterns withPercentiles(Map<String, int> percentiles) => ChartPatterns(
        level: level,
        steps: steps,
        counts: counts,
        at: at,
        fullCrossovers: fullCrossovers,
        upFootswitches: upFootswitches,
        downFootswitches: downFootswitches,
        rhythm: rhythm,
        percentiles: percentiles,
      );

  /// Occurrences per 100 steps, what [percentiles] rank.
  double rate(Pattern p) => steps == 0 ? 0 : _rounded(counts[p]! * 100 / steps);

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

  const PatternLevels(this.rates);

  factory PatternLevels.of(Iterable<(Modes, ChartPatterns)> charts) {
    final rates = <Modes, Map<int, Map<Pattern, List<double>>>>{
      for (final m in Modes.values) m: {}
    };
    for (final (mode, c) in charts) {
      final byPattern = rates[mode]!
          .putIfAbsent(c.level, () => {for (final p in Pattern.values) p: []});
      for (final p in Pattern.values) {
        byPattern[p]!.add(c.rate(p));
      }
    }
    for (final levels in rates.values) {
      for (final byPattern in levels.values) {
        for (final list in byPattern.values) {
          list.sort();
        }
      }
    }
    return PatternLevels(rates);
  }

  /// [c] ranked against same-style charts within a level either side.
  ChartPatterns rank(Modes mode, ChartPatterns c) {
    final cohort = [
      for (int l = c.level - 1; l <= c.level + 1; l++)
        if (rates[mode]![l] case final byPattern?) byPattern
    ];
    return c.withPercentiles({
      for (final p in Pattern.values)
        p.name: percentileOf(c.rate(p), [for (final b in cohort) ...b[p]!]),
    });
  }

  static String _key(Modes m) => m == Modes.singles ? "sp" : "dp";

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
      });

  Map<String, dynamic> toJson() => {
        "schema": kPatternsSchema,
        for (final MapEntry(key: m, value: levels) in rates.entries)
          _key(m): {
            for (final MapEntry(key: level, value: byPattern) in levels.entries)
              "$level": {for (final e in byPattern.entries) e.key.name: e.value}
          }
      };
}

class PatternsLoader {
  /// Loaded with the first song and kept: it covers the whole library.
  static PatternLevels? _levels;

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
