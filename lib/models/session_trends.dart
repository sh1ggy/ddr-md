/// Name: SessionTrends
/// Parent: SessionTrendsPage
/// Description: Weeks of play read against your usual on the same charts
/// (the session summary's model, so a week of harder charts isn't a bad
/// week): the week as a whole, its days, each cab side with the lamp you
/// gave it, each level, timing and goals. Missing weeks stay unknown.
library;

import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/pad_rating.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';

/// Weeks the form lines cover.
const kTrendWeeks = 8;

DateTime trendDay(DateTime date) {
  final d = date.toLocal();
  return DateTime(d.year, d.month, d.day);
}

/// A Monday-to-Sunday week in local calendar dates, [end] exclusive.
class TrendWindow {
  const TrendWindow(this.start, this.end);
  final DateTime start, end;

  factory TrendWindow.containing(DateTime date) {
    final day = trendDay(date);
    final monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
    return TrendWindow(
        monday, DateTime(monday.year, monday.month, monday.day + 7));
  }

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
  TrendWindow shift(int weeks) => TrendWindow(
      DateTime(start.year, start.month, start.day + 7 * weeks),
      DateTime(end.year, end.month, end.day + 7 * weeks));

  @override
  bool operator ==(Object other) =>
      other is TrendWindow && other.start == start;
  @override
  int get hashCode => start.hashCode;
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
      {this.mode = Modes.singles,
      this.level,
      this.chart,
      this.venueId,
      this.cabinetId,
      this.side});
  final Modes mode;
  final int? level, venueId, cabinetId;
  final String? chart;
  final PadSide? side;
  bool matches(TrendPlay p) =>
      p.play.mode == mode &&
      (level == null || p.level == level) &&
      (chart == null || p.chart == chart) &&
      (venueId == null || p.venueId == venueId) &&
      (cabinetId == null || p.cabinetId == cabinetId) &&
      (side == null || p.side == side);
}

/// Everything the page reads, loaded once.
typedef TrendSources = ({
  List<TrendPlay> plays,
  ScoreModel model,
  Map<int, Cabinet> cabinets,
  List<PadRating> ratings,
  List<CardGain> gains,
  // By session id.
  Map<String, GoalProgress> goals,
});

/// A scored play against its usual, weighted as the session summary does.
typedef TrendPoint = ({TrendPlay play, double usual, double weight});

/// The weighted average of [points]' score less their usual.
double? gapOf(Iterable<TrendPoint> points) {
  var sum = 0.0, weight = 0.0;
  for (final p in points) {
    sum += (p.play.play.score! - p.usual) * p.weight;
    weight += p.weight;
  }
  return weight == 0 ? null : sum / weight;
}

double? _mean(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

typedef PadSideId = (int cabinet, PadSide side);

class TrendWeek {
  TrendWeek({
    required this.window,
    required this.plays,
    required this.points,
    required this.upscores,
    required this.biggest,
    required this.cards,
  });
  final TrendWindow window;
  final List<TrendPlay> plays;
  final List<TrendPoint> points;
  final int upscores, cards;

  /// The week's largest gain on a chart's earlier best play.
  final ({TrendPlay play, int gain})? biggest;

  double? get gap => gapOf(points);
  int get sessions => plays.map((p) => p.visitKey).toSet().length;

  /// Monday first; null where nothing scored.
  List<double?> get days => [
        for (var i = 0; i < 7; i++)
          gapOf(points.where((p) =>
              trendDay(p.play.play.playedAt) ==
              DateTime(window.start.year, window.start.month,
                  window.start.day + i))),
      ];

  double? sideGap(PadSideId side) => gapOf(points
      .where((p) => p.play.cabinetId == side.$1 && p.play.side == side.$2));

  /// Each level played, easiest first, against the usual.
  Map<int, double> get levels {
    final levels = {
      for (final p in points)
        if (p.play.level case final l?) l
    }.toList()
      ..sort();
    return {
      for (final l in levels) l: gapOf(points.where((p) => p.play.level == l))!
    };
  }

  /// Timing landed, FAST negative, and how widely it spread.
  double? get timingMs => _mean([
        for (final p in plays)
          if (p.timing?.offBeatMs case final v?) v
      ]);
  double? get spreadMs => _mean([
        for (final p in plays)
          if (p.timing?.trueVariationMs case final v? when v.isFinite) v
      ]);
}

/// [sources]' plays under [filter], ready to read a week at a time.
class TrendHistory {
  TrendHistory(this.sources, this.filter) {
    final plays = sources.plays.where(filter.matches).toList();
    final byVisit = <String, List<TrendPlay>>{};
    for (final p in plays) {
      byVisit.putIfAbsent(p.visitKey, () => []).add(p);
    }
    for (final visit in byVisit.values) {
      final scored = [
        for (final p in visit.reversed)
          if (p.play.score != null) p
      ];
      if (scored.isEmpty) continue;
      final of = {for (final p in scored) p.play: p};
      for (final p in sources.model.summarize([
        for (final p in scored) p.play,
      ]).points) {
        _points.add((play: of[p.play]!, usual: p.usual, weight: p.weight));
      }
    }
    // Each chart's plays in order, to tell an upscore by what came before.
    final charts = <String, List<RecentPlay>>{};
    for (final p in sources.model.history.reversed) {
      if (p.score != null) charts.putIfAbsent(p.recordId, () => []).add(p);
    }
    for (final p in plays) {
      final score = p.play.score;
      if (score == null) continue;
      final before = [
        for (final e in charts[p.play.recordId] ?? const <RecentPlay>[])
          if (e.playedAt.isBefore(p.play.playedAt)) e.score!
      ];
      final best = sources.model.best(p.play);
      if (before.isNotEmpty) {
        final was = before.reduce((a, b) => a > b ? a : b);
        if (score > was) _upscores[p] = score - was;
      } else if (best != null && score >= best) {
        // First synced play holding the chart's best: an upscore, by how
        // much unknown.
        _upscores[p] = null;
      }
    }
    _plays.addAll(plays);
  }

  final TrendSources sources;
  final TrendFilter filter;
  final _plays = <TrendPlay>[];
  final _points = <TrendPoint>[];
  final _upscores = <TrendPlay, int?>{};
  final _weeks = <TrendWindow, TrendWeek>{};

  bool get isEmpty => _plays.isEmpty;

  TrendWeek week(TrendWindow w) => _weeks.putIfAbsent(w, () {
        bool inWeek(TrendPlay p) => w.contains(p.play.playedAt);
        final plays = _plays.where(inWeek).toList();
        final ups = {
          for (final MapEntry(:key, :value) in _upscores.entries)
            if (inWeek(key)) key: value
        };
        final best = ups.entries
            .where((e) => e.value != null)
            .fold<MapEntry<TrendPlay, int?>?>(
                null, (a, e) => a == null || e.value! > a.value! ? e : a);
        return TrendWeek(
          window: w,
          plays: plays,
          points: _points.where((p) => inWeek(p.play)).toList(),
          upscores: ups.length,
          biggest: best == null ? null : (play: best.key, gain: best.value!),
          cards: sources.gains
              .where((g) =>
                  g.mode == filter.mode &&
                  w.contains(g.playedAt) &&
                  plays.any((p) =>
                      p.play.song == g.song &&
                      p.play.difficulty == g.difficulty &&
                      p.play.playedAt.difference(g.playedAt).inSeconds.abs() <=
                          60))
              .length,
        );
      });

  /// The [kTrendWeeks] weeks ending with [last], oldest first.
  List<TrendWeek> span(TrendWindow last) => [
        for (var i = kTrendWeeks - 1; i >= 0; i--) week(last.shift(-i)),
      ];

  /// Every side played in [weeks], most sessions first.
  List<({PadSideId id, int sessions, int weeks})> sides(List<TrendWeek> weeks) {
    final sessions = <PadSideId, Set<String>>{};
    final played = <PadSideId, Set<TrendWindow>>{};
    for (final w in weeks) {
      for (final p in w.points) {
        if (p.play.cabinetId == null || p.play.side == null) continue;
        final id = (p.play.cabinetId!, p.play.side!);
        sessions.putIfAbsent(id, () => {}).add(p.play.visitKey);
        played.putIfAbsent(id, () => {}).add(w.window);
      }
    }
    return [
      for (final id in sessions.keys)
        (id: id, sessions: sessions[id]!.length, weeks: played[id]!.length)
    ]..sort((a, b) => b.sessions.compareTo(a.sessions));
  }

  /// The latest lamp given to [side] in [w].
  ClearLamp? lamp(PadSideId side, TrendWindow w) => sources.ratings
      .where((r) =>
          r.cabinet.id == side.$1 && r.side == side.$2 && w.contains(r.at))
      .fold<PadRating?>(null, (a, r) => a == null || r.at.isAfter(a.at) ? r : a)
      ?.lamp;

  /// Goals set in [w]'s sessions for this mode, oldest first.
  List<GoalProgress> goals(TrendWindow w) => [
        for (final key in {
          for (final p in sources.plays)
            if (w.contains(p.play.playedAt)) p.visitKey
        })
          if (sources.goals[key] case final g? when g.goal.mode == filter.mode)
            g
      ];
}

/// A side's eight weeks in one line, from its weekly gaps (oldest first)
/// and the lamps given those weeks.
String sideRead(List<double?> gaps, List<ClearLamp?> lamps) {
  final known = [
    for (final g in gaps)
      if (g != null) g
  ];
  if (known.length < 2) return 'Not enough weeks to call a trend.';
  final at = [
    for (var i = 0; i < gaps.length; i++)
      if (gaps[i] != null) i
  ];
  final last = at.sublist(at.length < 3 ? 0 : at.length - 3);
  if (last.length == 3) {
    final [a, b, c] = [for (final i in last) gaps[i]!];
    final good = [
      for (final i in last)
        if (lamps[i] case final l? when l.index >= ClearLamp.gfc.index) l
    ];
    if (a > b && b > c && c < 0) {
      return good.isEmpty
          ? 'Down three weeks running.'
          : 'Sliding for three weeks while you rated it well. The pad may be '
              'drifting, or you are.';
    }
    if (a < b && b < c && c > 0) return 'Up three weeks running.';
  }
  if (known.every((g) => g >= 0)) {
    return 'Above your usual every week you played it.';
  }
  if (known.every((g) => g < 0)) {
    return 'Below your usual every week you played it.';
  }
  final mean = known.reduce((a, b) => a + b) / known.length;
  return mean.abs() < 3000
      ? 'Close to your usual.'
      : mean > 0
          ? 'Above your usual more often than not.'
          : 'Below your usual more often than not.';
}
