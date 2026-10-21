/// Name: SetSummaryCard
/// Parent: SessionPage
/// Description: How the latest set of e-amusement plays went as a whole: its
/// average score against what your history says you'd average on that same
/// mix of charts, the bests it set, and, when it fell inside a session run in
/// the app, that session's venue and timing.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// How many plays the level's model counts as when blended into a chart's
/// own earlier plays, so one lucky or bad play doesn't set the bar.
const _levelWeight = 2;
// Bests a level needs before its average stands in for a chart.
const _minLevelCharts = 3;

class SetSummary {
  SetSummary({
    required this.plays,
    required this.points,
    required this.level,
    required this.bests,
    this.session,
    this.timingMs,
  });

  /// The set, newest first.
  final List<RecentPlay> plays;

  /// Each play with a score, a level and a usual.
  final List<({RecentPlay play, int level, double usual})> points;

  /// The charts' average level.
  final double? level;

  /// Charts whose best a play in the set reached.
  final int bests;

  /// The session run in the app while the set was played.
  final PlaySession? session;

  /// That session's average timing offset; negative is fast.
  final double? timingMs;

  /// The set's average score, over [points].
  double? get average => points.isEmpty
      ? null
      : points.fold<double>(0, (a, p) => a + p.play.score!) / points.length;

  /// What history says you'd average on the same charts.
  double? get usual => points.isEmpty
      ? null
      : points.fold<double>(0, (a, p) => a + p.usual) / points.length;

  double? get gap =>
      average == null || usual == null ? null : average! - usual!;
}

/// The latest set in [history] (newest first) against what came before it.
///
/// A chart's usual is its earlier plays' average, blended with the level's
/// model: your average best at that mode and level, less how far plays
/// usually land below their chart's best. The model covers charts you've
/// never had a play of synced, which is most of them early on.
SetSummary? summarizeLatestSet(
  List<RecentPlay> history,
  List<ScoreRecord> records,
  int? Function(String? song, Modes mode, String difficulty) levelOf,
) {
  if (history.isEmpty) return null;
  final set = groupPlaySets(history).first;
  final before = history.skip(set.length).where((p) => p.score != null);

  double mean(Iterable<num> s) => s.fold<double>(0, (a, b) => a + b) / s.length;
  final bests = {for (final r in records) r.id: r.score};
  final levels = <String, int?>{};
  int? level(RecentPlay p) => levels.putIfAbsent(
      p.recordId, () => levelOf(p.song, p.mode, p.difficulty));

  final levelBests = <String, List<int>>{};
  for (final r in records) {
    final l = levelOf(r.song, r.mode, r.difficulty);
    if (r.score != null && l != null) {
      levelBests.putIfAbsent('${r.mode.name}:$l', () => []).add(r.score!);
    }
  }
  final belowBest = [
    for (final p in before)
      if (bests[p.recordId] != null) p.score! - bests[p.recordId]!,
  ];
  final offset = belowBest.isEmpty ? 0.0 : mean(belowBest);

  final byChart = <String, List<int>>{};
  for (final p in before) {
    byChart.putIfAbsent(p.recordId, () => []).add(p.score!);
  }

  double? modelOf(Modes mode, int level) {
    final peers = levelBests['${mode.name}:$level'];
    return peers != null && peers.length >= _minLevelCharts
        ? mean(peers) + offset
        : null;
  }

  double? usualOf(RecentPlay p, int level) {
    final chart = byChart[p.recordId];
    final model = modelOf(p.mode, level);
    if (chart == null) return model;
    if (model == null) return mean(chart);
    return (chart.length * mean(chart) + _levelWeight * model) /
        (chart.length + _levelWeight);
  }

  final points = [
    for (final p in set)
      if ((p.score, level(p)) case (final _?, final l?))
        if (usualOf(p, l) case final u?) (play: p, level: l, usual: u),
  ];
  final known = [
    for (final p in set)
      if (level(p) case final l?) l,
  ];
  return SetSummary(
    plays: set,
    points: points,
    level: known.isEmpty ? null : mean(known),
    bests: {
      for (final p in set)
        if (p.score != null &&
            bests[p.recordId] != null &&
            p.score! >= bests[p.recordId]!)
          p.recordId,
    }.length,
  );
}

/// The session in [sessions] that was running while [set] (newest first)
/// was played: plays land on e-amusement a little after the credit, so a
/// session counts until a set break past its end.
PlaySession? sessionFor(List<RecentPlay> set, List<PlaySession> sessions) {
  final first = set.last.playedAt;
  final last = set.first.playedAt;
  for (final s in sessions) {
    final end = (s.endedAt ?? DateTime.now()).add(kSetBreak);
    if (!first.isAfter(end) && !last.isBefore(s.startedAt)) return s;
  }
  return null;
}

class SetSummaryCard extends StatelessWidget {
  const SetSummaryCard({super.key});

  static Future<SetSummary?> _load() async {
    final summary = summarizeLatestSet(
      await DatabaseProvider.getRecentPlays(),
      await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse),
      (song, mode, difficulty) => chartOf(song, mode, difficulty).level,
    );
    if (summary == null) return null;
    final session = sessionFor(
        summary.plays, await DatabaseProvider.getSessions(limit: 10));
    if (session == null) return summary;
    final timing = await DatabaseProvider.getSessionPlays(session.id);
    return SetSummary(
      plays: summary.plays,
      points: summary.points,
      level: summary.level,
      bests: summary.bests,
      session: session,
      timingMs: timing.isEmpty
          ? null
          : timing.map((t) => t.averageMs).reduce((a, b) => a + b) /
              timing.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final synced = context.select<EamuseSyncState, int>((s) => s.revision);
    final sessions = context.select<SessionState, int>((s) => s.revision);
    return FutureBuilder<SetSummary?>(
      key: ValueKey((synced, sessions)),
      future: _load(),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) return const SizedBox.shrink();
        return HomeCard(
          title: summary.session?.venue.name ?? 'Session summary',
          icon: summary.session == null ? Icons.insights : Icons.place,
          children: [SetHeader(summary.plays), _Body(summary)],
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.summary);

  final SetSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final gap = summary.gap;
    final up = isDark ? Colors.green.shade300 : Colors.green.shade700;
    final timing = summary.timingMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gap == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Not enough history yet to say how this set went.'),
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
          _GapTimeline(summary, up: up, down: scheme.error),
        ],
        const SizedBox(height: 10),
        Row(children: [
          _Stat(
            label: 'Avg level',
            child: summary.level == null
                ? const _StatText('–')
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: LevelNumber(
                        level: summary.level!.round(),
                        difficulty: _mostPlayed(summary.plays),
                        height: 20),
                  ),
          ),
          _Stat(
            label: 'Bests',
            child: Row(children: [
              const BestBadge(),
              const SizedBox(width: 6),
              _StatText('${summary.bests}'),
            ]),
          ),
          if (summary.session != null)
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

/// The difficulty most of [plays] were on, to colour their average level.
String _mostPlayed(List<RecentPlay> plays) {
  final counts = <String, int>{};
  for (final p in plays) {
    counts[p.difficulty] = (counts[p.difficulty] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
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
/// of the usual line, with a running average through them.
class _GapTimeline extends StatelessWidget {
  const _GapTimeline(this.summary, {required this.up, required this.down});

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
              [for (final p in plays) p.play.score! - p.usual],
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
            child: summary.points.length < summary.plays.length
                ? Text(
                    '${summary.points.length} of ${summary.plays.length} '
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
  _GapPainter(this.gaps,
      {required this.up, required this.down, required this.line});

  final List<double> gaps;
  final Color up, down, line;

  // Plays either side of each point the running average spans.
  static const _window = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // The gaps' own range, always taking in the usual line.
    final top = gaps.fold<double>(1, max), bottom = gaps.fold<double>(-1, min);
    const r = 3.5;
    double x(int i) => gaps.length == 1
        ? size.width / 2
        : r + i / (gaps.length - 1) * (size.width - 2 * r);
    double y(double g) =>
        r + (top - g) / (top - bottom) * (size.height - 2 * r);
    final mid = y(0);

    final dash = Paint()
      ..color = line.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 6) {
      canvas.drawLine(Offset(dx, mid), Offset(dx + 3, mid), dash);
    }

    for (var i = 0; i < gaps.length; i++) {
      canvas.drawCircle(Offset(x(i), y(gaps[i])), r,
          Paint()..color = (gaps[i] >= 0 ? up : down).withValues(alpha: 0.55));
    }

    final trend = Path();
    for (var i = 0; i < gaps.length; i++) {
      final from = max(0, i - _window), to = min(gaps.length, i + _window + 1);
      final avg = gaps.sublist(from, to).reduce((a, b) => a + b) / (to - from);
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
  bool shouldRepaint(_GapPainter old) => old.gaps != gaps;
}
