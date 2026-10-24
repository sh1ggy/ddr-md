/// Name: SessionSummary
/// Parent: LastSessionCard, VisitPage
/// Description: How a session's e-amusement plays went as a whole: their
/// average score against what your history says you'd average on that same
/// mix of charts, broken down by level, over each play's gap in play order,
/// with the average level, level range, upscores and, when timing was
/// logged, its offset.
/// Failed plays (an E) and far-off ones count for less.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
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

/// How far a play's gap can sit from the set's median gap before it counts
/// for less: three of the set's usual spread, and never under this. Past
/// it a play's weight falls off so it can pull the average no further, and
/// one fumbled chart doesn't sink the set.
const _minOutlierGap = 50000.0;

class SetSummary {
  SetSummary(
      {required this.points,
      required this.level,
      this.lowest,
      this.highest,
      required this.upscores});

  /// Each play with a score and a usual, newest first, with its level when
  /// known and what it counts for in the averages: less when failed or far
  /// off the rest.
  final List<({RecentPlay play, int? level, double usual, double weight})>
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

  /// [points] with a level, grouped by it, easiest first: the level's
  /// average and usual, its plays and what they count for together.
  List<LevelSummary> get byLevel {
    final groups = <int, List<(int score, double usual, double weight)>>{};
    for (final p in points) {
      if (p.level case final l?) {
        groups.putIfAbsent(l, () => []).add((p.play.score!, p.usual, p.weight));
      }
    }
    return [
      for (final l in groups.keys.toList()..sort())
        (
          level: l,
          average: _weightedMean([for (final (s, _, w) in groups[l]!) (s, w)]),
          usual: _weightedMean([for (final (_, u, w) in groups[l]!) (u, w)]),
          plays: groups[l]!.length,
          weight: groups[l]!.fold(0, (a, p) => a + p.$3),
        ),
    ];
  }
}

typedef LevelSummary = ({
  int level,
  double average,
  double usual,
  int plays,
  double weight
});

double _mean(Iterable<num> s) => s.fold<double>(0, (a, b) => a + b) / s.length;

double _median(Iterable<double> s) {
  final o = s.toList()..sort();
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

double _weightedMean(Iterable<(num, double)> s) =>
    s.fold<double>(0, (a, e) => a + e.$1 * e.$2) /
    s.fold<double>(0, (a, e) => a + e.$2);

/// What you usually score, from your synced plays and bests.
///
/// A chart's usual is its earlier plays' average, blended with a model of
/// it: its best from before the set, or failing that your average best at
/// that mode and level, less how far plays usually land below their chart's
/// best. The model covers charts you've never had a play of synced, which
/// is most of them. Failed plays count for [_failWeight] of a play
/// throughout.
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

    // Charts whose best may have been set in or after the set, so isn't the
    // best it was played against.
    final reached = {
      for (final p in history)
        if (!p.playedAt.isBefore(first) &&
            p.score != null &&
            best(p) != null &&
            p.score! >= best(p)!)
          p.recordId,
    };

    double? usualOf(RecentPlay p) {
      final chart = byChart[p.recordId];
      final peers = _levelBests['${p.mode.name}:${level(p)}'];
      final model = best(p) != null && !reached.contains(p.recordId)
          ? best(p)! + offset
          : peers != null && peers.length >= _minLevelCharts
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
    final scored = [
      for (final p in plays)
        if (p.score case final s?)
          if (usualOf(p) case final u?)
            (play: p, level: level(p), usual: u, gap: s - u),
    ];
    // The spread is the cleared plays' median distance from their median
    // gap, scaled to a standard deviation.
    final cleared = [
      for (final p in scored)
        if (!p.play.failed) p.gap
    ];
    final gaps = cleared.isEmpty ? [for (final p in scored) p.gap] : cleared;
    final mid = gaps.isEmpty ? 0.0 : _median(gaps);
    final limit = gaps.isEmpty
        ? 0.0
        : max<double>(_minOutlierGap,
            3 * 1.4826 * _median([for (final g in gaps) (g - mid).abs()]));
    return SetSummary(
      points: [
        for (final p in scored)
          (
            play: p.play,
            level: p.level,
            usual: p.usual,
            weight: _weight(p.play) * min(1.0, limit / (p.gap - mid).abs()),
          ),
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

/// [summary] of [plays] (newest first), with the [timing] logged in the
/// session. With timing, a toggle swaps the score chart for the timing one.
class SessionSummaryBody extends StatefulWidget {
  const SessionSummaryBody(this.summary,
      {super.key,
      required this.plays,
      this.timing,
      this.timed = false,
      this.detailed = false});

  final SetSummary summary;
  final List<RecentPlay> plays;
  final List<TimingPlay>? timing;
  // Whether the session could log timing, to show its stat even when empty.
  final bool timed;
  // Each level as its own you-vs-usual bar rather than a tile.
  final bool detailed;

  @override
  State<SessionSummaryBody> createState() => _SessionSummaryBodyState();
}

class _SessionSummaryBodyState extends State<SessionSummaryBody> {
  bool _showTiming = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final plays = widget.plays;
    final timed = widget.timed;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final gap = summary.gap;
    final up = isDark ? Colors.green.shade300 : Colors.green.shade700;
    final logged = widget.timing ?? const <TimingPlay>[];
    final timing = logged.isEmpty
        ? null
        : logged.map((t) => t.averageMs).reduce((a, b) => a + b) /
            logged.length;
    final showTiming = _showTiming && timing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Score')),
                ButtonSegment(value: true, label: Text('Timing')),
              ],
              selected: {showTiming},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _showTiming = v.first),
            ),
          ),
        if (showTiming)
          _TimingChart(logged, mean: timing, isDark: isDark)
        else if (gap == null)
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
          if (summary.byLevel case final levels when levels.isNotEmpty) ...[
            widget.detailed
                ? _LevelBars(levels, up: up, down: scheme.error)
                : _LevelChips(levels, up: up, down: scheme.error),
            const SizedBox(height: 12),
          ],
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

/// Each level's average on one score axis beside its usual, easiest first:
/// a tick at the usual, a dot at the average and the gap filled between
/// them, with the gap and the level's plays at the end.
class _LevelBars extends StatelessWidget {
  const _LevelBars(this.levels, {required this.up, required this.down});

  final List<LevelSummary> levels;
  final Color up, down;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    // From a round 10k under the lowest score shown up to the 1,000,000
    // ceiling, shared so the levels line up.
    final lowest = levels.map((l) => min(l.usual, l.average)).reduce(min);
    final lo = ((lowest - 20000) / 10000).floor() * 10000.0;
    const hi = 1000000.0;
    double at(double score) => ((score - lo) / (hi - lo)).clamp(0, 1);
    String gap(double g) =>
        '${g >= 0 ? '+' : '−'}${formatScore(g.abs().round())}';
    return Column(children: [
      for (final l in levels)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: ColorFiltered(
                colorFilter: kGreyLevel,
                child: LevelNumber(
                    level: l.level, difficulty: 'EXPERT', height: 16),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                final colour = l.average >= l.usual ? up : down;
                return SizedBox(
                  height: 18,
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
                      left: min(at(l.usual), at(l.average)) * w,
                      width: (at(l.average) - at(l.usual)).abs() * w,
                      top: 6,
                      height: 6,
                      child: ColoredBox(color: colour.withValues(alpha: 0.6)),
                    ),
                    Positioned(
                      left: at(l.usual) * w - 1,
                      top: 0,
                      width: 2,
                      height: 18,
                      child: ColoredBox(color: scheme.onSurfaceVariant),
                    ),
                    Positioned(
                      left: at(l.average) * w - 6,
                      top: 3,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: colour, shape: BoxShape.circle),
                      ),
                    ),
                  ]),
                );
              }),
            ),
            SizedBox(
              width: 92,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: gap(l.average - l.usual),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: l.average >= l.usual ? up : down),
                  ),
                  TextSpan(text: ' ×${l.plays}', style: muted),
                ]),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ]),
        ),
      Row(children: [
        const SizedBox(width: 28),
        Text('${(lo / 1000).round()}k', style: muted),
        const Spacer(),
        Text('1M', style: muted),
        const SizedBox(width: 92),
      ]),
    ]);
  }
}

/// Each level's gap from its usual as a tile, easiest first, tinted by
/// whether it came in over or under and fainter the less its plays count
/// for.
class _LevelChips extends StatelessWidget {
  const _LevelChips(this.levels, {required this.up, required this.down});

  final List<LevelSummary> levels;
  final Color up, down;

  // What a level's plays need to count for to get the full tint.
  static const _fullWeight = 3.0;
  static const _columns = 5, _spacing = 6.0;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    String k(double gap) {
      final a = gap.abs() / 1000;
      return '${gap >= 0 ? '+' : '−'}'
          '${a < 10 ? a.toStringAsFixed(1) : a.round()}k';
    }

    return LayoutBuilder(builder: (context, box) {
      final across = min(levels.length, _columns);
      final w = (box.maxWidth - _spacing * (across - 1)) / across;
      return Wrap(
        spacing: _spacing,
        runSpacing: _spacing,
        children: [
          for (final (l, gap) in [
            for (final l in levels) (l, l.average - l.usual)
          ])
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: (gap >= 0 ? up : down).withValues(
                    alpha: 0.06 + 0.12 * min(1, l.weight / _fullWeight)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ColorFiltered(
                    colorFilter: kGreyLevel,
                    child: LevelNumber(
                        level: l.level, difficulty: 'EXPERT', height: 14),
                  ),
                  Text(' ×${l.plays}', style: muted),
                ]),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    k(gap),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: gap >= 0 ? up : down,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ]),
            ),
        ],
      );
    });
  }
}

/// The session's timing: its mean offset, then each logged play's offset in
/// the order played around the on-time line, SLOW above and FAST below.
class _TimingChart extends StatelessWidget {
  const _TimingChart(this.timing, {required this.mean, required this.isDark});

  final List<TimingPlay> timing;
  final double mean;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final ordered = [...timing]
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    final fast = kFastColor(isDark), slow = kSlowColor(isDark);
    String at(TimingPlay t) =>
        formatTime12(DateTime.parse(t.playedAt).toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${mean.abs().toStringAsFixed(1)} ms',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: mean < 0 ? fast : slow,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    '${mean < 0 ? 'FAST' : 'SLOW'} on average · '
                    '${ordered.length} logged',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant))),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: CustomPaint(
            painter: _GapPainter(
              [for (final t in ordered) (t.averageMs, 1.0, false)],
              up: slow,
              down: fast,
              line: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          Text(at(ordered.first), style: muted),
          const Spacer(),
          Text(at(ordered.last), style: muted),
        ]),
      ],
    );
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
              [
                for (final p in plays)
                  (p.play.score! - p.usual, p.weight, p.play.failed)
              ],
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

  // Each play's gap, what it counts for and whether it failed.
  final List<(double, double, bool)> points;
  final Color up, down, line;

  // Plays either side of each point the running average spans.
  static const _window = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // The full-weight plays' range, always taking in the usual line; a
    // failed or far-off play past it sits on the edge rather than squashing
    // the rest.
    final cleared = [
      for (final (g, w, _) in points)
        if (w == 1) g
    ];
    final ranged =
        cleared.isEmpty ? [for (final (g, _, _) in points) g] : cleared;
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
      final (g, _, failed) = points[i];
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
      final avg = _weightedMean(
          [for (final (g, w, _) in points.sublist(from, to)) (g, w)]);
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
