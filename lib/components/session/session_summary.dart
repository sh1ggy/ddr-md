/// Name: SessionSummary
/// Parent: LastSessionCard, VisitPage
/// Description: How a session's e-amusement plays went as a whole: their
/// average score against what your history says you'd average on that same
/// mix of charts, broken down by level, over each play in order by credit,
/// with the average level, level range, upscores and, when timing was
/// logged, its offset.
/// Failed plays (an E) and far-off ones count for less.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_wrap.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// How many plays the level's model counts as when blended into a chart's
/// own earlier plays, so one lucky or bad play doesn't set the bar.
const _levelWeight = 2;
// Bests a level needs before its average stands in for a chart.
const _minLevelCharts = 3;

/// What a failed play (an E) counts for against a cleared one: its score
/// stops where the lifebar ran out, so it says little about your scoring.
const _failWeight = 0.25;

/// How far FAST or SLOW a timing is when it takes the full colour.
const _fullTimingMs = 10.0;

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
      required this.upscores,
      this.levels = const {}});

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

  /// Each play's level, where known.
  final Map<RecentPlay, int> levels;

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
      levels: {
        for (final p in plays)
          if (level(p) case final l?) p: l,
      },
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
      this.detailed = false,
      this.credits = const [],
      this.gains = const [],
      this.onCollected,
      this.onPlay});

  final SetSummary summary;
  final List<RecentPlay> plays;
  final List<TimingPlay>? timing;
  // Whether the session could log timing, to show its stat even when empty.
  final bool timed;
  // Each level as its own you-vs-usual bar rather than a tile.
  final bool detailed;
  // The credits logged in the session, to split the play strip by.
  final List<Credit> credits;
  // What the session's plays did to your cards, and opening its wrap.
  final List<CardGain> gains;
  final VoidCallback? onCollected;
  // A play tapped on the strip.
  final ValueChanged<RecentPlay>? onPlay;

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
    final pop = FloorPop.of(context);
    final up = pop.up, down = pop.down;
    final logged = widget.timing ?? const <TimingPlay>[];
    final timing = logged.isEmpty
        ? null
        : logged.map((t) => t.offBeatMs).reduce((a, b) => a + b) /
            logged.length;
    final showTiming = _showTiming && timing != null;
    final (played, matched) = reconcileTiming(plays, logged);
    // Each credit's plays, oldest credit and play first.
    final groups = [
      for (final (_, g)
          in groupByCredit(played, widget.credits, matched).reversed)
        g.reversed.toList()
    ];
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
          _TimingChart(groups, matched,
              levels: summary.levels,
              mean: timing,
              isDark: isDark,
              onPlay: widget.onPlay)
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
                style: FloorPop.readout(34, color: gap >= 0 ? up : down),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('vs your usual', style: muted)),
            ],
          ),
          const SizedBox(height: 8),
          if (summary.byLevel case final levels when levels.isNotEmpty) ...[
            widget.detailed
                ? _LevelBars(levels, up: up, down: down)
                : _LevelChips(_scoreChips(levels, up: up, down: down)),
            const SizedBox(height: 12),
          ],
          _PlayStrip(
            groups,
            value: (p) =>
                switch (summary.points.where((e) => e.play == p).firstOrNull) {
              final e? => (e.play.score! - e.usual, e.play.failed),
              null => null,
            },
            full: 50000,
            up: up,
            down: down,
            counted: 'compared',
            onPlay: widget.onPlay,
          ),
        ],
        const SizedBox(height: 10),
        Row(spacing: 6, children: [
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const UpscoreBadge(),
              const SizedBox(width: 6),
              _StatText('${summary.upscores}'),
            ]),
          ),
          if (timed)
            _Stat(
              label: 'Timing',
              tint: timing == null
                  ? null
                  : (timing < 0 ? kFastColor(isDark) : kSlowColor(isDark))
                      .withValues(
                          alpha: 0.06 +
                              0.24 * min(1, timing.abs() / _fullTimingMs)),
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
        if (widget.gains.isNotEmpty) ...[
          const SizedBox(height: 6),
          CollectedTile(widget.gains, onTap: widget.onCollected),
        ],
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
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: kGreyLevel,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, l) in levels.indexed) ...[
            if (i > 0) const _StatText(' – '),
            LevelNumber(level: l, difficulty: 'EXPERT', height: 20),
          ],
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.child, this.tint});

  final String label;
  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: tint ?? scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          SizedBox(
            height: 22,
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          ),
        ]),
      ),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: FloorPop.readout(17, color: color));
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

/// A level's tile: its numeral and plays over [text] in [colour], on
/// [tint].
typedef _Chip = ({int level, int plays, String text, Color colour, Color tint});

/// Each level as a tile, easiest first, five to a row.
class _LevelChips extends StatelessWidget {
  const _LevelChips(this.chips);

  final List<_Chip> chips;

  static const _columns = 5, _spacing = 6.0;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return LayoutBuilder(builder: (context, box) {
      final across = min(chips.length, _columns);
      final w = (box.maxWidth - _spacing * (across - 1)) / across;
      return Wrap(
        spacing: _spacing,
        runSpacing: _spacing,
        children: [
          for (final c in chips)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: c.tint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ColorFiltered(
                    colorFilter: kGreyLevel,
                    child: LevelNumber(
                        level: c.level, difficulty: 'EXPERT', height: 14),
                  ),
                  Text(' ×${c.plays}', style: muted),
                ]),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c.text,
                    style: FloorPop.readout(17, color: c.colour),
                  ),
                ),
              ]),
            ),
        ],
      );
    });
  }
}

/// [levels] as chips of their gap from usual, fainter the less a level's
/// plays count for.
List<_Chip> _scoreChips(List<LevelSummary> levels,
    {required Color up, required Color down}) {
  // What a level's plays need to count for to get the full tint.
  const fullWeight = 3.0;
  final chips = <_Chip>[];
  for (final l in levels) {
    final gap = l.average - l.usual;
    final k = gap.abs() / 1000;
    final colour = gap >= 0 ? up : down;
    chips.add((
      level: l.level,
      plays: l.plays,
      text: '${gap >= 0 ? '+' : '−'}'
          '${k < 10 ? k.toStringAsFixed(1) : k.round()}k',
      colour: colour,
      tint:
          colour.withValues(alpha: 0.06 + 0.12 * min(1, l.weight / fullWeight)),
    ));
  }
  return chips;
}

/// Each level of [plays] as a chip of its mean timing, FAST or SLOW, deeper
/// the further off; grey when none of its plays had timing logged.
List<_Chip> _timingChips(Iterable<RecentPlay> plays,
    Map<RecentPlay, TimingPlay> matched, Map<RecentPlay, int> levels,
    {required Color fast, required Color slow, required Color none}) {
  final byLevel = <int, List<double>>{};
  for (final p in plays) {
    if (levels[p] case final l?) {
      final ms = byLevel.putIfAbsent(l, () => []);
      if (matched[p] case final t?) ms.add(t.offBeatMs);
    }
  }
  final chips = <_Chip>[];
  for (final l in byLevel.keys.toList()..sort()) {
    final ms = byLevel[l]!;
    if (ms.isEmpty) {
      chips.add((
        level: l,
        plays: 0,
        text: '–',
        colour: none.withValues(alpha: 0.5),
        tint: none.withValues(alpha: 0.06),
      ));
      continue;
    }
    final m = ms.reduce((a, b) => a + b) / ms.length;
    final colour = m < 0 ? fast : slow;
    chips.add((
      level: l,
      plays: ms.length,
      text: '${m.abs().toStringAsFixed(1)}${m < 0 ? 'F' : 'S'}',
      colour: colour,
      tint: colour.withValues(
          alpha: 0.06 + 0.24 * min(1, m.abs() / _fullTimingMs)),
    ));
  }
  return chips;
}

/// The session's timing: its mean offset, by level, then every play in
/// order as a
/// cell split by credit, pink for SLOW and cyan for FAST, deeper the
/// further off, and grey where no timing was logged.
class _TimingChart extends StatelessWidget {
  const _TimingChart(this.groups, this.matched,
      {required this.levels,
      required this.mean,
      required this.isDark,
      this.onPlay});

  // Each credit's plays, oldest credit and play first.
  final List<List<RecentPlay>> groups;
  final Map<RecentPlay, TimingPlay> matched;
  // Each play's level, where known.
  final Map<RecentPlay, int> levels;
  final double mean;
  final bool isDark;
  final ValueChanged<RecentPlay>? onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fast = kFastColor(isDark), slow = kSlowColor(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${mean.abs().toStringAsFixed(1)} ms',
              style: FloorPop.readout(34, color: mean < 0 ? fast : slow),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${mean < 0 ? 'FAST' : 'SLOW'} on average',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant))),
          ],
        ),
        const SizedBox(height: 8),
        if (_timingChips(groups.expand((g) => g), matched, levels,
                fast: fast, slow: slow, none: scheme.onSurface)
            case final chips when chips.isNotEmpty) ...[
          _LevelChips(chips),
          const SizedBox(height: 12),
        ],
        _TimingSpread(matched.values, fast: fast, slow: slow),
        const SizedBox(height: 12),
        _PlayStrip(
          groups,
          value: (p) => switch (matched[p]) {
            final t? => (t.offBeatMs, false),
            null => null,
          },
          full: _fullTimingMs,
          up: slow,
          down: fast,
          counted: 'timed',
          onPlay: onPlay,
        ),
      ],
    );
  }
}

/// Every play in the order played as a cell, split into its credits:
/// [up] or [down] by the sign of its [value], deeper the further off up to
/// [full], outlined when failed and grey when it has no value. Tapping a
/// cell runs [onPlay] with its play.
class _PlayStrip extends StatelessWidget {
  const _PlayStrip(this.groups,
      {required this.value,
      required this.full,
      required this.up,
      required this.down,
      required this.counted,
      this.onPlay});

  // Each credit's plays, oldest credit and play first.
  final List<List<RecentPlay>> groups;
  final (double, bool)? Function(RecentPlay) value;
  final double full;
  final Color up, down;
  // What a play with a value is, for the count under the strip.
  final String counted;
  final ValueChanged<RecentPlay>? onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final played = groups.expand((g) => g).toList();
    final cells = [
      for (final g in groups) [for (final p in g) value(p)]
    ];
    final valued = cells.expand((c) => c).nonNulls.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onTapUp: onPlay == null
                ? null
                : (d) {
                    final rects = _StripPainter.layout(
                        [for (final g in groups) g.length],
                        Size(box.maxWidth, 28));
                    final at = d.localPosition.dx;
                    var best = 0;
                    for (final (i, r) in rects.indexed) {
                      if ((r.center.dx - at).abs() <
                          (rects[best].center.dx - at).abs()) {
                        best = i;
                      }
                    }
                    onPlay!(played[best]);
                  },
            child: SizedBox(
              height: 28,
              child: CustomPaint(
                size: Size.infinite,
                painter: _StripPainter(cells,
                    full: full,
                    up: up,
                    down: down,
                    none: scheme.surfaceContainerHighest),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(formatTime12(played.first.playedAt.toLocal()), style: muted),
          Expanded(
            child: valued < played.length
                ? Text('$valued of ${played.length} plays $counted',
                    textAlign: TextAlign.center, style: muted)
                : const SizedBox(),
          ),
          Text(formatTime12(played.last.playedAt.toLocal()), style: muted),
        ]),
      ],
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.credits,
      {required this.full,
      required this.up,
      required this.down,
      required this.none});

  // Each credit's plays in order: a play's gap and whether it failed, or
  // null when it wasn't compared.
  final List<List<(double, bool)?>> credits;
  // How far off a play is when its cell takes the full colour.
  final double full;
  final Color up, down, none;
  static const _cellGap = 2.0, _creditGap = 8.0;

  /// Each cell's rect, in order, for credits of [counts] plays.
  static List<Rect> layout(List<int> counts, Size size) {
    final cells = counts.fold<int>(0, (a, c) => a + c);
    final gaps =
        (cells - counts.length) * _cellGap + (counts.length - 1) * _creditGap;
    final w = (size.width - gaps) / cells;
    final rects = <Rect>[];
    var x = 0.0;
    for (final count in counts) {
      for (var i = 0; i < count; i++) {
        rects.add(Rect.fromLTWH(x, 0, w, size.height));
        x += w + _cellGap;
      }
      x += _creditGap - _cellGap;
    }
    return rects;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rects = layout([for (final c in credits) c.length], size).iterator;
    for (final credit in credits) {
      for (final play in credit) {
        rects.moveNext();
        final rect =
            RRect.fromRectAndRadius(rects.current, const Radius.circular(3));
        switch (play) {
          case null:
            canvas.drawRRect(rect, Paint()..color = none);
          case (final gap, final failed):
            final colour = (gap >= 0 ? up : down)
                .withValues(alpha: 0.25 + 0.75 * min(1, gap.abs() / full));
            canvas.drawRRect(
                failed ? rect.deflate(0.75) : rect,
                Paint()
                  ..color = colour
                  ..style = failed ? PaintingStyle.stroke : PaintingStyle.fill
                  ..strokeWidth = 1.5);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.credits != credits;
}

/// Where the set's steps landed, drawn like the song page's Sync curve:
/// every timed play's average and variation summed into one spread around
/// the beat, FAST to the left and SLOW to the right.
class _TimingSpread extends StatelessWidget {
  const _TimingSpread(this.timing, {required this.fast, required this.slow});

  final Iterable<TimingPlay> timing;
  final Color fast, slow;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final caption = TextStyle(fontSize: 11, color: pop.haze);
    final plays = [
      for (final t in timing) (t.offBeatMs, max(1.0, t.trueVariationMs))
    ];
    final range = plays
        .fold<double>(30, (a, p) => max(a, p.$1.abs() + 2 * p.$2))
        .ceilToDouble();
    final density = [
      for (var x = -range; x <= range; x++)
        plays.fold<double>(
            0, (a, p) => a + exp(-pow(x - p.$1, 2) / (2 * p.$2 * p.$2)) / p.$2),
    ];
    final peak = density.reduce(max);
    final mean =
        plays.fold<double>(0, (a, p) => a + p.$1) / max(1, plays.length);
    final colour = mean < 0 ? fast : slow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: LineChart(
            LineChartData(
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              extraLinesData: ExtraLinesData(verticalLines: [
                // Dead on the beat, then where the set really landed.
                VerticalLine(
                  x: 0,
                  color: pop.haze,
                  strokeWidth: 1.5,
                  dashArray: [3, 4],
                  label: VerticalLineLabel(
                    show: true,
                    alignment:
                        mean < 0 ? Alignment.topRight : Alignment.topLeft,
                    style: caption.copyWith(fontSize: 10),
                    labelResolver: (_) => 'on time',
                  ),
                ),
                VerticalLine(
                  x: mean,
                  color: colour,
                  strokeWidth: 2,
                  label: VerticalLineLabel(
                    show: true,
                    alignment:
                        mean < 0 ? Alignment.topLeft : Alignment.topRight,
                    style: caption.copyWith(
                        fontSize: 10,
                        color: colour,
                        fontWeight: FontWeight.w700),
                    labelResolver: (_) => 'you',
                  ),
                ),
              ]),
              clipData: const FlClipData.all(),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              minX: -range,
              maxX: range,
              minY: 0,
              maxY: 108,
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final (i, d) in density.indexed)
                      FlSpot(i - range, d / peak * 100),
                  ],
                  barWidth: 2,
                  color: colour,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: colour.withValues(alpha: 0.15)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('fast',
                style:
                    caption.copyWith(color: fast, fontWeight: FontWeight.w600)),
            Text('offset from beat (ms)', style: caption),
            Text('slow',
                style:
                    caption.copyWith(color: slow, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}
