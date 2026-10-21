/// Name: SessionSummary
/// Parent: LastSessionCard, VisitPage
/// Description: How a session's e-amusement plays went as a whole: their
/// average score against what your history says you'd average on that same
/// mix of charts, as a you-vs-usual bar over each play's gap in play order,
/// with the average level, level range, upscores and, when timing was
/// logged, its offset.
/// Failed plays (an E) count for less.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

/// How many plays the level's model counts as when blended into a chart's
/// own earlier plays, so one lucky or bad play doesn't set the bar.
const _levelWeight = 2;
// Bests a level needs before its average stands in for a chart.
const _minLevelCharts = 3;

/// What a failed play (an E) counts for against a cleared one: its score
/// stops where the lifebar ran out, so it says little about your scoring.
const _failWeight = 0.25;

double _weight(RecentPlay p) => p.failed ? _failWeight : 1;

class SetSummary {
  SetSummary(
      {required this.points,
      required this.level,
      this.lowest,
      this.highest,
      required this.upscores});

  /// Each play with a score, a level and a usual, newest first, with what
  /// it counts for in the averages.
  final List<({RecentPlay play, int level, double usual, double weight})>
      points;

  /// The charts' average level.
  final double? level;

  /// The easiest and hardest charts' levels.
  final int? lowest, highest;

  /// Charts a play upscored: set the best they have now.
  final int upscores;

  /// The average score, over [points].
  double? get average => points.isEmpty
      ? null
      : _weightedMean([for (final p in points) (p.play.score!, p.weight)]);

  /// What history says you'd average on the same charts.
  double? get usual => points.isEmpty
      ? null
      : _weightedMean([for (final p in points) (p.usual, p.weight)]);

  double? get gap =>
      average == null || usual == null ? null : average! - usual!;
}

double _mean(Iterable<num> s) => s.fold<double>(0, (a, b) => a + b) / s.length;

double _weightedMean(Iterable<(num, double)> s) =>
    s.fold<double>(0, (a, e) => a + e.$1 * e.$2) /
    s.fold<double>(0, (a, e) => a + e.$2);

/// What you usually score, from your synced plays and bests.
///
/// A chart's usual is its earlier plays' average, blended with the level's
/// model: your average best at that mode and level, less how far plays
/// usually land below their chart's best. The model covers charts you've
/// never had a play of synced, which is most of them early on. Failed plays
/// count for [_failWeight] of a play throughout.
class ScoreModel {
  ScoreModel(this.history, List<ScoreRecord> records, this.levelOf)
      : _bests = {for (final r in records) r.id: r.score} {
    for (final r in records) {
      final l = levelOf(r.song, r.mode, r.difficulty);
      if (r.score != null && l != null) {
        _levelBests.putIfAbsent('${r.mode.name}:$l', () => []).add(r.score!);
      }
    }
  }

  /// Every synced play, newest first.
  final List<RecentPlay> history;
  final int? Function(String? song, Modes mode, String difficulty) levelOf;

  final Map<String, int?> _bests;
  final _levelBests = <String, List<int>>{};
  final _levels = <String, int?>{};

  /// Each chart's synced best, by [RecentPlay.recordId].
  Map<String, int?> get bests => _bests;

  int? best(RecentPlay p) => _bests[p.recordId];

  int? level(RecentPlay p) => _levels.putIfAbsent(
      p.recordId, () => levelOf(p.song, p.mode, p.difficulty));

  /// [plays] (newest first) against every play before the first of them.
  SetSummary summarize(List<RecentPlay> plays) {
    final first = plays.last.playedAt;
    final before =
        history.where((p) => p.score != null && p.playedAt.isBefore(first));
    final belowBest = [
      for (final p in before)
        if (best(p) != null) (p.score! - best(p)!, _weight(p)),
    ];
    final offset = belowBest.isEmpty ? 0.0 : _weightedMean(belowBest);
    final byChart = <String, List<(int, double)>>{};
    for (final p in before) {
      byChart.putIfAbsent(p.recordId, () => []).add((p.score!, _weight(p)));
    }

    double? usualOf(RecentPlay p, int level) {
      final chart = byChart[p.recordId];
      final peers = _levelBests['${p.mode.name}:$level'];
      final model = peers != null && peers.length >= _minLevelCharts
          ? _mean(peers) + offset
          : null;
      if (chart == null) return model;
      if (model == null) return _weightedMean(chart);
      final plays = chart.fold<double>(0, (a, e) => a + e.$2);
      return (plays * _weightedMean(chart) + _levelWeight * model) /
          (plays + _levelWeight);
    }

    final known = [
      for (final p in plays)
        if (level(p) case final l?) l,
    ];
    return SetSummary(
      points: [
        for (final p in plays)
          if ((p.score, level(p)) case (final _?, final l?))
            if (usualOf(p, l) case final u?)
              (play: p, level: l, usual: u, weight: _weight(p)),
      ],
      level: known.isEmpty ? null : _mean(known),
      lowest: known.isEmpty ? null : known.reduce(min),
      highest: known.isEmpty ? null : known.reduce(max),
      upscores: {
        for (final p in plays)
          if (p.score != null && best(p) != null && p.score! >= best(p)!)
            p.recordId,
      }.length,
    );
  }
}

/// [summary] of [plays] (newest first), with [timingMs] when timing was
/// logged in the session: its average offset, negative is fast.
class SessionSummaryBody extends StatelessWidget {
  const SessionSummaryBody(this.summary,
      {super.key, required this.plays, this.timingMs, this.timed = false});

  final SetSummary summary;
  final List<RecentPlay> plays;
  final double? timingMs;
  // Whether the session could log timing, to show its stat even when empty.
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final gap = summary.gap;
    final up = isDark ? Colors.green.shade300 : Colors.green.shade700;
    final timing = timingMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gap == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Not enough history yet to say how this went.'),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${gap >= 0 ? '+' : '−'}${formatScore(gap.abs().round())}',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: gap >= 0 ? up : scheme.error,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('vs your usual', style: muted)),
            ],
          ),
          const SizedBox(height: 8),
          _UsualBar(summary, up: up, down: scheme.error),
          const SizedBox(height: 12),
          _GapTimeline(summary,
              played: plays.length, up: up, down: scheme.error),
        ],
        const SizedBox(height: 10),
        Row(children: [
          _Stat(
            label: 'Avg level',
            child: summary.level == null
                ? const _StatText('–')
                : _Levels([summary.level!.round()]),
          ),
          _Stat(
            label: 'Levels',
            child: switch ((summary.lowest, summary.highest)) {
              (final lo?, final hi?) => _Levels([lo, if (hi != lo) hi]),
              _ => const _StatText('–'),
            },
          ),
          _Stat(
            label: 'Upscores',
            child: Row(children: [
              const UpscoreBadge(),
              const SizedBox(width: 6),
              _StatText('${summary.upscores}'),
            ]),
          ),
          if (timed)
            _Stat(
              label: 'Timing',
              child: _StatText(
                timing == null
                    ? '–'
                    : '${timing.abs().toStringAsFixed(1)} '
                        '${timing < 0 ? 'FAST' : 'SLOW'}',
                color: timing == null
                    ? null
                    : timing < 0
                        ? kFastColor(isDark)
                        : kSlowColor(isDark),
              ),
            ),
        ]),
      ],
    );
  }
}

/// [levels] in the cabinet's numerals, greyed since they span charts, with
/// a dash between two.
class _Levels extends StatelessWidget {
  const _Levels(this.levels);

  final List<int> levels;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        // Four stats share the row on a phone; shrinks rather than
        // overflows on a wide range like 9 – 19.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ColorFiltered(
            colorFilter: kGreyLevel,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (i, l) in levels.indexed) ...[
                if (i > 0) const _StatText(' – '),
                LevelNumber(level: l, difficulty: 'EXPERT', height: 20),
              ],
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()]));
}

/// The set's average on a score axis beside its usual: a tick at the usual,
/// a dot at the average and the gap filled between them.
class _UsualBar extends StatelessWidget {
  const _UsualBar(this.summary, {required this.up, required this.down});

  final SetSummary summary;
  final Color up, down;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final usual = summary.usual!, average = summary.average!;
    // From a round 10k under the lower of the two up to the 1,000,000 ceiling.
    final lo = ((min(usual, average) - 20000) / 10000).floor() * 10000.0;
    const hi = 1000000.0;
    double at(double score) => ((score - lo) / (hi - lo)).clamp(0, 1);
    final colour = average >= usual ? up : down;
    String k(double score) => '${(score / 1000).round()}k';
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      Widget label(String text, double x) => Positioned(
            left: (x * w - 40).clamp(0, w - 80),
            width: 80,
            top: 22,
            child: Text(text, textAlign: TextAlign.center, style: muted),
          );
      return SizedBox(
        height: 38,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Positioned(
            left: min(at(usual), at(average)) * w,
            width: (at(average) - at(usual)).abs() * w,
            top: 6,
            height: 6,
            child: ColoredBox(color: colour.withValues(alpha: 0.6)),
          ),
          Positioned(
            left: at(usual) * w - 1,
            top: 0,
            width: 2,
            height: 18,
            child: ColoredBox(color: scheme.onSurfaceVariant),
          ),
          Positioned(
            left: at(average) * w - 7,
            top: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          ),
          label('usual ${k(usual)}', at(usual)),
          label('you ${k(average)}', at(average)),
        ]),
      );
    });
  }
}

/// Each play's gap from its usual in the order played, as dots either side
/// of the usual line (rings for failed plays), with a running average
/// through them.
class _GapTimeline extends StatelessWidget {
  const _GapTimeline(this.summary,
      {required this.played, required this.up, required this.down});

  // Plays in the session, compared or not.
  final int played;

  final SetSummary summary;
  final Color up, down;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final plays = summary.points.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: CustomPaint(
            painter: _GapPainter(
              [for (final p in plays) (p.play.score! - p.usual, p.weight)],
              up: up,
              down: down,
              line: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          Text(formatTime12(plays.first.play.playedAt.toLocal()), style: muted),
          Expanded(
            child: summary.points.length < played
                ? Text(
                    '${summary.points.length} of $played '
                    'plays compared',
                    textAlign: TextAlign.center,
                    style: muted)
                : const SizedBox(),
          ),
          Text(formatTime12(plays.last.play.playedAt.toLocal()), style: muted),
        ]),
      ],
    );
  }
}

class _GapPainter extends CustomPainter {
  _GapPainter(this.points,
      {required this.up, required this.down, required this.line});

  // Each play's gap and what it counts for: under 1 is a failed play.
  final List<(double, double)> points;
  final Color up, down, line;

  // Plays either side of each point the running average spans.
  static const _window = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // The cleared plays' range, always taking in the usual line; a failed
    // play past it sits on the edge rather than squashing the rest.
    final cleared = [
      for (final (g, w) in points)
        if (w == 1) g
    ];
    final ranged = cleared.isEmpty ? [for (final (g, _) in points) g] : cleared;
    final top = ranged.fold<double>(1, max),
        bottom = ranged.fold<double>(-1, min);
    const r = 3.5;
    double x(int i) => points.length == 1
        ? size.width / 2
        : r + i / (points.length - 1) * (size.width - 2 * r);
    double y(double g) =>
        (r + (top - g) / (top - bottom) * (size.height - 2 * r))
            .clamp(r, size.height - r);
    final mid = y(0);

    final dash = Paint()
      ..color = line.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 6) {
      canvas.drawLine(Offset(dx, mid), Offset(dx + 3, mid), dash);
    }

    for (var i = 0; i < points.length; i++) {
      final (g, w) = points[i];
      final failed = w < 1;
      canvas.drawCircle(
          Offset(x(i), y(g)),
          failed ? r - 0.75 : r,
          Paint()
            ..color = (g >= 0 ? up : down).withValues(alpha: 0.55)
            ..style = failed ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 1.5);
    }

    final trend = Path();
    for (var i = 0; i < points.length; i++) {
      final from = max(0, i - _window),
          to = min(points.length, i + _window + 1);
      final avg = _weightedMean(points.sublist(from, to));
      i == 0 ? trend.moveTo(x(i), y(avg)) : trend.lineTo(x(i), y(avg));
    }
    canvas.drawPath(
        trend,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_GapPainter old) => old.points != points;
}
