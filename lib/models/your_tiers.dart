/// Name: YourTiers
/// Parent: YourTiersPage, SongDetails, the song list
/// Description: The player's own tier list: where they put each Singles chart
/// they've played among its level, on the same rungs as the calculated tier
/// (.00–.95 in .05 steps, .10 at level 19). A setting picks which tier rows
/// and numerals show: theirs, the calculated one, or their circle's median.
/// From how their placements differ from the calculated tiers, the phone
/// works out which kinds of chart they find harder or easier (their lean)
/// and nudges unplayed charts into a "for you" tier. Nothing here goes into
/// the tier model.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/foundation.dart';

/// Hundredths between rungs at [level].
int tierStep(int level) => level == 19 ? 10 : 5;

/// [hundredths] on [level]'s nearest rung below, inside the level.
int onRung(int level, int hundredths) {
  final step = tierStep(level);
  return ((hundredths ~/ step) * step).clamp(0, 100 - step);
}

/// Every rung of [level], hardest first.
List<int> rungsOf(int level) =>
    [for (var h = 100 - tierStep(level); h >= 0; h -= tierStep(level)) h];

/// ".75", as rungs read beside the level numeral.
String rungLabel(int hundredths) => '.${'$hundredths'.padLeft(2, '0')}';

/// Which tier rows and numerals show.
enum TierShown { mine, calc, circle }

enum TierKind { mine, forYou, calc, circle }

typedef ShownTier = ({int hundredths, TierKind kind});

/// A placement: the chart's level when it was placed, and its rung.
typedef TierPlacement = ({int level, int hundredths, DateTime placedAt});

/// A chart, as placements key it: song name and in-game difficulty (EXPERT).
typedef TierChart = (String song, String difficulty);

class YourTiers {
  /// Bumped when placements, circle lists or the lean change.
  static final revision = ValueNotifier(0);

  static var _placements = <TierChart, TierPlacement>{};

  /// Placements changed since the circle last got them.
  static bool unshared = false;

  static Map<TierChart, TierPlacement> get all => _placements;

  static TierShown get shown =>
      TierShown.values[Settings.getInt(Settings.tierShownKey)
          .clamp(0, TierShown.values.length - 1)];

  static Future<void> setShown(TierShown s) async {
    await Settings.setInt(Settings.tierShownKey, s.index);
    revision.value++;
  }

  static Future<void> load() async {
    final rows = await DatabaseProvider.getTierPlacements();
    _placements = {
      for (final r in rows)
        if (r['mode'] == Modes.singles.name)
          (r['song'] as String, r['difficulty'] as String): (
            level: r['level'] as int,
            hundredths: r['hundredths'] as int,
            placedAt: DateTime.tryParse(r['placedAt'] as String? ?? '') ??
                DateTime.now(),
          )
    };
    TierLean.invalidate();
    revision.value++;
  }

  /// The chart's placement, while it's still at the level it was placed at.
  static TierPlacement? of(String song, String difficulty, int level) {
    final p = _placements[(song, difficulty)];
    return p?.level == level ? p : null;
  }

  /// Places the chart on [hundredths]'s rung, or with null takes it off.
  static Future<void> place(
      String song, String difficulty, int level, int? hundredths) async {
    final rung = hundredths == null ? null : onRung(level, hundredths);
    await DatabaseProvider.setTierPlacement(
        song: song,
        mode: Modes.singles.name,
        difficulty: difficulty,
        level: level,
        hundredths: rung);
    _placements = {..._placements};
    if (rung == null) {
      _placements.remove((song, difficulty));
    } else {
      _placements[(song, difficulty)] =
          (level: level, hundredths: rung, placedAt: DateTime.now());
    }
    unshared = true;
    TierLean.invalidate();
    revision.value++;
  }

  /// Only charts with a play on record can be placed.
  static bool canPlace(String song, String difficulty) =>
      ChartBests.forChart(song, Modes.singles, difficulty) != null;

  // -- The circle's lists, as CircleState last loaded them.
  static var _circle = <String, Map<TierChart, TierPlacement>>{};

  static Map<String, Map<TierChart, TierPlacement>> get circleLists => _circle;

  static void setCircle(Map<String, Map<TierChart, TierPlacement>> lists) {
    _circle = lists;
    revision.value++;
  }

  /// Everyone in the circle who placed the chart at [level], by person id.
  static Map<String, int> circleRungs(
          String song, String difficulty, int level) =>
      {
        for (final MapEntry(:key, :value) in _circle.entries)
          if (value[(song, difficulty)] case final p? when p.level == level)
            key: p.hundredths
      };

  /// The circle's median rung on the chart, null when nobody placed it.
  static int? circleMedian(String song, String difficulty, int level) {
    final rungs = circleRungs(song, difficulty, level).values.toList()..sort();
    if (rungs.isEmpty) return null;
    final mid = rungs.length ~/ 2;
    return rungs.length.isOdd
        ? rungs[mid]
        : onRung(level, (rungs[mid - 1] + rungs[mid]) ~/ 2);
  }
}

extension ShownTiers on SongInfo {
  /// The chart at [index] of [mode]'s availableTypes, as placements key it,
  /// with its official level.
  ({String difficulty, String key, int level})? tierChartAt(
      Modes mode, int index) {
    final levels = mode == Modes.singles ? singles : doubles;
    final types = levels.availableTypes;
    if (types.isEmpty) return null;
    final key = types[index.clamp(0, types.length - 1)];
    final level = levels.toJson()[key] as int?;
    if (level == null) return null;
    return (difficulty: kInGameDifficultyNames[key]!, key: key, level: level);
  }

  /// The tier the setting shows for the chart at [index]. Placements and the
  /// circle are Singles only; Doubles keeps the calculated tier.
  ShownTier? shownTierFor(Modes mode, int index) {
    final calc = scoringTierFor(mode, index);
    final calcTier = calc == null
        ? null
        : (hundredths: calc.hundredths, kind: TierKind.calc);
    if (mode != Modes.singles) return calcTier;
    final chart = tierChartAt(mode, index);
    if (chart == null) return calcTier;
    switch (YourTiers.shown) {
      case TierShown.calc:
        return calcTier;
      case TierShown.circle:
        final median =
            YourTiers.circleMedian(name, chart.difficulty, chart.level);
        return median == null
            ? calcTier
            : (hundredths: median, kind: TierKind.circle);
      case TierShown.mine:
        if (YourTiers.of(name, chart.difficulty, chart.level) case final p?) {
          return (hundredths: p.hundredths, kind: TierKind.mine);
        }
        if (calc == null ||
            ChartBests.forChart(name, mode, chart.difficulty) != null) {
          return calcTier;
        }
        final nudged =
            TierLean.forYou(this, chart.key, chart.level, calc.hundredths);
        return nudged == null || nudged == calc.hundredths
            ? calcTier
            : (hundredths: nudged, kind: TierKind.forYou);
    }
  }

  /// [shownTierFor] as a decimal tier, for sorting.
  double? shownTierValue(Modes mode, int index) {
    final t = shownTierFor(mode, index);
    final level = tierChartAt(mode, index)?.level;
    return t == null || level == null ? null : level + t.hundredths / 100;
  }
}

/// How the player's placements lean from the calculated tiers, per kind of
/// chart: for each category, a least-squares slope of (their rung minus the
/// calculated one) against how far the chart sits from its level's middle
/// in that category. A positive lean means they rate charts heavy in it
/// harder. Shrunk toward zero while there are few placements.
class TierLean {
  /// Placements needed before unplayed charts get a "for you" tier.
  static const minPlaced = 8;

  /// A chart's stand-out categories: this far from the middle of its level.
  static const _standout = .4;

  static const _shrink = 10;

  static Map<ChartCategory, double>? _lean;
  static int _placed = 0;
  static Future<void>? _computing;

  static void invalidate() {
    _lean = null;
    _computing = null;
  }

  /// Per category, in hundredths for a chart at the far end of its level.
  static Map<ChartCategory, double> get lean => _lean ?? const {};

  /// How many placements the lean comes from.
  static int get placed => _placed;

  static double _z(ChartPatterns c, ChartCategory k) =>
      ((c.categoryPercentiles[k] ?? 50) - 50) / 50;

  /// Works out the lean, reading the placed songs' patterns.
  static Future<void> ensure() => _computing ??= _compute();

  static Future<void> _compute() async {
    final samples = <(ChartPatterns, double)>[];
    for (final MapEntry(key: (song, difficulty), value: p)
        in YourTiers.all.entries) {
      final info = Songs.list.where((s) => s.name == song).firstOrNull;
      if (info == null) continue;
      final types = info.singles.availableTypes;
      final i =
          types.indexWhere((t) => kInGameDifficultyNames[t] == difficulty);
      if (i < 0) continue;
      final calc = info.scoringTierFor(Modes.singles, i);
      if (calc == null || calc.tier.floor() != p.level) continue;
      final patterns = (await PatternsLoader.cached(song))
          ?.chartFor(Modes.singles, types[i]);
      if (patterns == null || patterns.categoryPercentiles.isEmpty) continue;
      samples.add((patterns, (p.hundredths - calc.hundredths).toDouble()));
    }
    final n = samples.length;
    final lean = <ChartCategory, double>{};
    for (final k in kRankedCategories) {
      var xy = 0.0, xx = 0.0;
      for (final (c, d) in samples) {
        final z = _z(c, k);
        xy += z * d;
        xx += z * z;
      }
      if (xx < 1e-6) continue;
      lean[k] = (xy / xx * n / (n + _shrink)).clamp(-30.0, 30.0);
    }
    _lean = lean;
    _placed = n;
    YourTiers.revision.value++;
  }

  /// The chart's calculated rung moved by the player's lean on its
  /// stand-out categories, or null without enough to go on (or its
  /// patterns not loaded yet).
  static int? forYou(
      SongInfo song, String difficultyKey, int level, int calcHundredths) {
    final lean = _lean;
    if (lean == null) {
      ensure();
      return null;
    }
    if (_placed < minPlaced) return null;
    final c = PatternsLoader.loaded(song.name)
        ?.chartFor(Modes.singles, difficultyKey);
    if (c == null || c.categoryPercentiles.isEmpty) return null;
    final moves = [
      for (final MapEntry(key: k, value: l) in lean.entries)
        if (_z(c, k).abs() >= _standout) l * _z(c, k)
    ];
    if (moves.isEmpty) return null;
    final nudge = moves.reduce((a, b) => a + b) / moves.length;
    final step = tierStep(level);
    final moved = calcHundredths + (nudge / step).round() * step;
    return moved.clamp(0, 100 - step);
  }

  /// The categories leaning furthest either way, strongest first.
  static List<(ChartCategory, double)> strongest([int count = 5]) {
    final ranked = [
      for (final MapEntry(:key, :value) in lean.entries)
        if (value.abs() >= 2.5) (key, value)
    ]..sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    return ranked.take(count).toList();
  }

  /// Rounds a lean to the nearest .05 for showing.
  static int shown(double lean) => (lean / 5).round() * 5;

  /// Hundredths as a signed ".15".
  static String label(int hundredths) =>
      '${hundredths >= 0 ? '▲' : '▼'}${rungLabel(math.min(hundredths.abs(), 95))}';
}
