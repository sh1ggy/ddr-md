/// Name: SessionTrends
/// Parent: SessionTrendsPage
/// Description: Calendar windows, level-matched comparisons and daily averages
/// across visits. Missing history stays unknown rather than becoming zero.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';

enum TrendRange { week, fortnight, month }

enum TrendMetric { score, timing }

DateTime trendDay(DateTime date) {
  final d = date.toLocal();
  return DateTime(d.year, d.month, d.day);
}

class TrendWindow {
  const TrendWindow(this.start, this.end, this.range);
  final DateTime start, end; // Local calendar dates, end exclusive.
  final TrendRange range;

  factory TrendWindow.containing(DateTime date, TrendRange range) {
    final day = trendDay(date);
    if (range == TrendRange.month) {
      return TrendWindow(DateTime(day.year, day.month),
          DateTime(day.year, day.month + 1), range);
    }
    final monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
    // Fortnights share a stable Monday anchor, independent of navigation.
    final anchor = DateTime.utc(2020, 1, 6);
    final weeks = DateTime.utc(monday.year, monday.month, monday.day)
            .difference(anchor)
            .inDays ~/
        7;
    final start = range == TrendRange.fortnight && weeks.isOdd
        ? DateTime(monday.year, monday.month, monday.day - 7)
        : monday;
    return TrendWindow(
        start,
        DateTime(start.year, start.month,
            start.day + (range == TrendRange.week ? 7 : 14)),
        range);
  }

  int get days => DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(start.year, start.month, start.day))
      .inDays;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
  TrendWindow shift(int amount) {
    if (range == TrendRange.month) {
      return TrendWindow(DateTime(start.year, start.month + amount),
          DateTime(start.year, start.month + amount + 1), range);
    }
    return TrendWindow(
        DateTime(start.year, start.month, start.day + days * amount),
        DateTime(end.year, end.month, end.day + days * amount),
        range);
  }
}

class TrendPlay {
  const TrendPlay(this.play,
      {this.timing,
      this.venueId,
      this.cabinetId,
      this.side,
      required this.visitKey,
      this.level});
  final RecentPlay play;
  final TimingPlay? timing;
  final int? venueId, cabinetId, level;
  final PadSide? side;
  final String visitKey;
  // Timing-only stand-ins have a different Konami id: use the resolved chart.
  String get chart =>
      '${play.song ?? play.konamiId}:${play.mode.name}:${play.difficulty}';
}

/// Reuse the session page's timing reconciliation and credit attribution.
List<TrendPlay> trendPlays(
    List<Visit> visits,
    Map<String, List<TimingPlay>> timing,
    Map<String, List<Credit>> credits,
    ScoreModel model) {
  final result = <TrendPlay>[];
  for (final v in visits) {
    final id = v.session?.id;
    final (plays, matched) = reconcileTiming(v.plays, timing[id] ?? []);
    for (final (credit, group)
        in groupByCredit(plays, credits[id] ?? [], matched)) {
      for (final p in group) {
        final t = matched[p];
        result.add(TrendPlay(p,
            timing: t,
            venueId: v.session?.venue.id,
            cabinetId: t?.cabinetId ?? credit?.cabinet.id,
            side: t?.side ?? credit?.side,
            visitKey: v.key,
            level: model.level(p)));
      }
    }
  }
  return result..sort((a, b) => a.play.playedAt.compareTo(b.play.playedAt));
}

class TrendFilter {
  const TrendFilter(
      {this.mode,
      this.level,
      this.chart,
      this.venueId,
      this.cabinetId,
      this.side});
  final Modes? mode;
  final int? level, venueId, cabinetId;
  final String? chart;
  final PadSide? side;
  bool matches(TrendPlay p) =>
      (mode == null || p.play.mode == mode) &&
      (level == null || p.level == level) &&
      (chart == null || p.chart == chart) &&
      (venueId == null || p.venueId == venueId) &&
      (cabinetId == null || p.cabinetId == cabinetId) &&
      (side == null || p.side == side);
}

class TrendSample {
  const TrendSample(this.day, this.value, this.plays, this.observations);
  final DateTime day;
  final double? value;
  final int plays, observations;
}

typedef TrendLevel = ({Modes mode, int level});

class TrendLevelComparison {
  const TrendLevelComparison(this.group, this.previous, this.current,
      this.previousPlays, this.currentPlays);
  final TrendLevel group;
  final double previous, current;
  final int previousPlays, currentPlays;
  String get label =>
      '${group.mode == Modes.singles ? 'SP' : 'DP'} ${group.level}';
}

class TrendSummary {
  TrendSummary(
      {required this.samples,
      required this.current,
      required this.average,
      required this.observations,
      required this.comparison,
      required this.levels,
      required this.goodSets,
      required this.ratedSets});
  final List<TrendSample> samples;
  final List<TrendPlay> current;

  /// Actual average over this period's cleared scores or logged timing.
  final double? average;
  final int observations;

  /// Positive means improvement. Each shared mode/level gets equal weight,
  /// so playing more easy songs cannot inflate the comparison.
  final double? comparison;
  final List<TrendLevelComparison> levels;
  final int goodSets, ratedSets;

  double? get comparedCurrent =>
      levels.isEmpty ? null : _mean(levels.map((l) => l.current));
  double? get comparedPrevious =>
      levels.isEmpty ? null : _mean(levels.map((l) => l.previous));
}

double? _value(TrendPlay p, TrendMetric metric) => metric == TrendMetric.score
    ? (p.play.failed ? null : p.play.score?.toDouble())
    : p.timing?.trueVariationMs;

List<double> _values(Iterable<TrendPlay> plays, TrendMetric metric) => [
      for (final p in plays)
        if (_value(p, metric) case final value?)
          if (value.isFinite) value,
    ];

double _mean(Iterable<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

Map<TrendLevel, List<double>> _byLevel(
    Iterable<TrendPlay> plays, TrendMetric metric) {
  final groups = <TrendLevel, List<double>>{};
  for (final p in plays) {
    final value = _value(p, metric);
    if (p.level != null && value != null && value.isFinite) {
      groups.putIfAbsent(
          (mode: p.play.mode, level: p.level!), () => []).add(value);
    }
  }
  return groups;
}

TrendSummary summarizeTrends(List<TrendPlay> all, TrendWindow window,
    TrendFilter filter, TrendMetric metric) {
  final filtered = all.where(filter.matches).toList();
  final current =
      filtered.where((p) => window.contains(p.play.playedAt)).toList();
  final previous = window.shift(-1);
  final now = _byLevel(current, metric);
  final before = _byLevel(
      filtered.where((p) => previous.contains(p.play.playedAt)), metric);
  final common = now.keys.where(before.containsKey).toList()
    ..sort((a, b) => a.mode.index == b.mode.index
        ? a.level.compareTo(b.level)
        : a.mode.index.compareTo(b.mode.index));
  final levels = [
    for (final group in common)
      TrendLevelComparison(group, _mean(before[group]!), _mean(now[group]!),
          before[group]!.length, now[group]!.length)
  ];
  final comparison = levels.isEmpty
      ? null
      : _mean([
          for (final l in levels)
            (l.current - l.previous) * (metric == TrendMetric.timing ? -1 : 1),
        ]);
  // A set is rated against earlier cleared scores at the same mode and
  // level. Different songs are valid peers; later plays cannot change it.
  final baseline = _byLevel(
      filtered.where((p) => p.play.playedAt.isBefore(window.start)),
      TrendMetric.score);
  double? scoreGap(Iterable<TrendPlay> plays) {
    final scores = _byLevel(plays, TrendMetric.score);
    final known = scores.keys.where(baseline.containsKey).toList();
    return known.isEmpty
        ? null
        : _mean([
            for (final group in known)
              _mean(scores[group]!) - _mean(baseline[group]!),
          ]);
  }

  final sets = <String, List<TrendPlay>>{};
  for (final p in current) {
    sets.putIfAbsent(p.visitKey, () => []).add(p);
  }
  final gaps = [
    for (final set in sets.values)
      if (scoreGap(set) case final gap?) gap
  ];
  final values = _values(current, metric);
  return TrendSummary(
    current: current,
    average: values.isEmpty ? null : _mean(values),
    observations: values.length,
    comparison: comparison,
    levels: levels,
    goodSets: gaps.where((g) => g >= 0).length,
    ratedSets: gaps.length,
    samples: [
      for (var i = 0; i < window.days; i++)
        (() {
          final day = DateTime(
              window.start.year, window.start.month, window.start.day + i);
          final plays =
              current.where((p) => trendDay(p.play.playedAt) == day).toList();
          final values = _values(plays, metric);
          return TrendSample(day, values.isEmpty ? null : _mean(values),
              plays.length, values.length);
        })(),
    ],
  );
}

/// Rounded chart bounds with roughly four intervals. Compute the interval
/// from the final visible range, including zero when requested.
class TrendAxis {
  const TrendAxis(this.min, this.max, this.step);
  final double min, max, step;
  factory TrendAxis.forValues(
    Iterable<double> values, {
    double minimumPadding = 1,
    double? floor,
    double? ceiling,
    bool includeZero = false,
  }) {
    final finite = values.where((v) => v.isFinite).toList();
    final low = finite.isEmpty ? 0.0 : finite.reduce(math.min);
    final high = finite.isEmpty ? 0.0 : finite.reduce(math.max);
    final pad = math.max(minimumPadding, (high - low) * .2);
    var lower = low - pad, upper = high + pad;
    if (includeZero) {
      lower = math.min(0, lower);
      upper = math.max(0, upper);
    }
    if (floor != null) lower = math.max(floor, lower);
    if (ceiling != null) upper = math.min(ceiling, upper);
    final span = math.max(minimumPadding, upper - lower);
    final magnitude =
        math.pow(10, (math.log(span / 4) / math.ln10).floor()).toDouble();
    final step =
        [1, 2, 5, 10].firstWhere((n) => n * magnitude >= span / 4) * magnitude;
    lower = (lower / step).floor() * step;
    upper = (upper / step).ceil() * step;
    if (floor != null) lower = math.max(floor, lower);
    if (ceiling != null) upper = math.min(ceiling, upper);
    if (upper <= lower) upper = lower + step;
    return TrendAxis(lower, upper, step);
  }
}
