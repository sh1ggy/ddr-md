/// Name: SessionTrends
/// Parent: SessionTrendsPage
/// Description: Calendar windows, chart-matched comparisons and daily trends
/// across visits. Missing history stays unknown rather than becoming zero.
library;

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
  const TrendSample(this.day, this.value, this.plays);
  final DateTime day;
  final double? value;
  final int plays;
}

class TrendSummary {
  TrendSummary(
      {required this.samples,
      required this.current,
      required this.comparison,
      required this.comparedCharts,
      required this.goodSets,
      required this.ratedSets});
  final List<TrendSample> samples;
  final List<TrendPlay> current;

  /// Equal weight per common chart; positive always means improvement.
  final double? comparison;
  final int comparedCharts, goodSets, ratedSets;
}

double? _value(TrendPlay p, TrendMetric metric) => metric == TrendMetric.score
    ? (p.play.failed ? null : p.play.score?.toDouble())
    : p.timing?.trueVariationMs;

double _mean(Iterable<double> values) =>
    values.reduce((a, b) => a + b) / values.length;
Map<String, double> _chartMeans(Iterable<TrendPlay> plays, TrendMetric metric) {
  final groups = <String, List<double>>{};
  for (final p in plays) {
    final value = _value(p, metric);
    if (value != null && value.isFinite) {
      groups.putIfAbsent(p.chart, () => []).add(value);
    }
  }
  return {for (final e in groups.entries) e.key: _mean(e.value)};
}

TrendSummary summarizeTrends(List<TrendPlay> all, TrendWindow window,
    TrendFilter filter, TrendMetric metric) {
  final filtered = all.where(filter.matches).toList();
  final current =
      filtered.where((p) => window.contains(p.play.playedAt)).toList();
  final previous = window.shift(-1);
  final now = _chartMeans(current, metric);
  final before = _chartMeans(
      filtered.where((p) => previous.contains(p.play.playedAt)), metric);
  final common = now.keys.where(before.containsKey).toList();
  final comparison = common.isEmpty
      ? null
      : _mean([
          for (final key in common)
            (now[key]! - before[key]!) *
                (metric == TrendMetric.timing ? -1 : 1),
        ]);
  // Freeze the baseline at the start of the window: later plays cannot
  // change the reference earlier days are measured against.
  final baseline = _chartMeans(
      filtered.where((p) => p.play.playedAt.isBefore(window.start)),
      TrendMetric.score);
  final plotBaseline = {...baseline};
  final firstDays = <String, DateTime>{};
  final seenDays = <String, Set<DateTime>>{};
  for (final p in current) {
    if (_value(p, TrendMetric.score) == null) continue;
    final day = trendDay(p.play.playedAt);
    seenDays.putIfAbsent(p.chart, () => {}).add(day);
    if (firstDays[p.chart] == null || day.isBefore(firstDays[p.chart]!)) {
      firstDays[p.chart] = day;
    }
  }
  // A first-ever period can still show progress on repeated charts. Their
  // first day's average is a fixed reference, never a fabricated prior score.
  for (final chart in firstDays.keys) {
    if (baseline.containsKey(chart) || seenDays[chart]!.length < 2) continue;
    plotBaseline[chart] = _chartMeans(
        current.where((p) =>
            p.chart == chart && trendDay(p.play.playedAt) == firstDays[chart]),
        TrendMetric.score)[chart]!;
  }
  double? scoreGap(Iterable<TrendPlay> plays, Map<String, double> reference) {
    final means = _chartMeans(plays, TrendMetric.score);
    final known = means.keys.where(reference.containsKey).toList();
    return known.isEmpty
        ? null
        : _mean([for (final k in known) means[k]! - reference[k]!]);
  }

  final sets = <String, List<TrendPlay>>{};
  for (final p in current) {
    sets.putIfAbsent(p.visitKey, () => []).add(p);
  }
  final gaps = [
    for (final set in sets.values)
      if (scoreGap(set, baseline) case final gap?) gap
  ];
  return TrendSummary(
    current: current,
    comparison: comparison,
    comparedCharts: common.length,
    goodSets: gaps.where((g) => g >= 0).length,
    ratedSets: gaps.length,
    samples: [
      for (var i = 0; i < window.days; i++)
        (() {
          final day = DateTime(
              window.start.year, window.start.month, window.start.day + i);
          final plays =
              current.where((p) => trendDay(p.play.playedAt) == day).toList();
          final timing = _chartMeans(plays, TrendMetric.timing);
          return TrendSample(
              day,
              metric == TrendMetric.score
                  ? scoreGap(plays, plotBaseline)
                  : timing.isEmpty
                      ? null
                      : _mean(timing.values),
              plays.length);
        })(),
    ],
  );
}
