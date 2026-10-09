/// Name: Pattern model + loader
/// Description: Each chart's pattern analysis ([analyseChart]) as stored in
/// assets/patterns/<name>.json by tool/generate_patterns.dart, with how the
/// chart ranks against others of its level. Read lazily when a song page opens.
library;

import 'dart:convert';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class ChartPatterns {
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
    required this.steps,
    required this.counts,
    required this.at,
    required this.fullCrossovers,
    required this.upFootswitches,
    required this.downFootswitches,
    required this.rhythm,
    this.percentiles = const {},
  });

  factory ChartPatterns.fromAnalysis(ChartAnalysis a) => ChartPatterns(
        steps: a.steps,
        counts: {for (final p in Pattern.values) p: a.footwork.count(p)},
        at: a.footwork.at,
        fullCrossovers: a.footwork.fullCrossovers,
        upFootswitches: a.footwork.upFootswitches,
        downFootswitches: a.footwork.downFootswitches,
        rhythm: a.rhythm,
      );

  ChartPatterns withPercentiles(Map<String, int> percentiles) => ChartPatterns(
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
  double rate(Pattern p) => steps == 0 ? 0 : counts[p]! * 100 / steps;

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
      percentiles:
          (j["percentiles"] as Map<String, dynamic>? ?? {}).cast<String, int>(),
    );
  }

  Map<String, dynamic> toJson() {
    double r(double v) => (v * 1000).roundToDouble() / 1000;
    return {
      "steps": steps,
      "counts": {for (final e in counts.entries) e.key.name: e.value},
      "at": {
        for (final e in at.entries)
          if (e.value.isNotEmpty) e.key.name: [for (final b in e.value) r(b)]
      },
      "full_crossovers": fullCrossovers,
      "up_footswitches": upFootswitches,
      "down_footswitches": downFootswitches,
      "rhythm": rhythm,
      "percentiles": percentiles,
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
        "sp": singles.map((k, v) => MapEntry(k, v.toJson())),
        "dp": doubles.map((k, v) => MapEntry(k, v.toJson())),
      };

  ChartPatterns? chartFor(Modes mode, String difficultyKey) =>
      (mode == Modes.singles ? singles : doubles)[difficultyKey];
}

class PatternsLoader {
  /// Null when the song has no analysis, so the page hides the section.
  static Future<SongPatterns?> load(String songName) async {
    try {
      final raw = await rootBundle.loadString(
        "assets/patterns/$songName.json",
        cache: false,
      );
      return SongPatterns.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
