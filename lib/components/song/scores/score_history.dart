/// Name: ScoreHistory
/// Parent: ScoresTab
/// Description: A chart's synced plays as a small line, oldest to newest, in
/// the difficulty's colour. Failed plays are hollow and the best is larger.
library;

import 'dart:math' as math;

import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class ScoreHistory extends StatelessWidget {
  const ScoreHistory({super.key, required this.plays, required this.color});

  /// Oldest first, all with a score.
  final List<RecentPlay> plays;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        width: double.infinity,
        child: CustomPaint(
          painter: _HistoryPainter(
              plays: plays,
              color: color,
              failColor: Theme.of(context).colorScheme.error,
              background: Theme.of(context).colorScheme.surfaceContainerLow),
        ),
      );
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(
      {required this.plays,
      required this.color,
      required this.failColor,
      required this.background});

  final List<RecentPlay> plays;
  final Color color, failColor, background;

  // Spacing stays even and a few plays don't stretch across the card; the
  // score range never shrinks below 50k so a 1k wobble doesn't look like a cliff.
  static const _maxStep = 28.0, _minRange = 50000, _r = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scores = [for (final p in plays) p.score!];
    // Fails sit on the bottom edge rather than squashing the passes flat.
    final passed = [
      for (final p in plays)
        if (!p.failed) p.score!
    ];
    final ranged = passed.isEmpty ? scores : passed;
    final hi = ranged.reduce(math.max), lo = ranged.reduce(math.min);
    final top = math.min(1000000, math.max(hi, lo + _minRange));
    final bottom = top - math.max(_minRange, hi - lo);
    final step = plays.length < 2
        ? 0.0
        : math.min(_maxStep, (size.width - 2 * _r - 2) / (plays.length - 1));
    final points = [
      for (final (i, s) in scores.indexed)
        Offset(
            _r + 1 + i * step,
            _r +
                1 +
                (size.height - 2 * _r - 2) *
                    ((top - s) / (top - bottom)).clamp(0.0, 1.0))
    ];

    canvas.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    final best = scores.indexOf(scores.reduce(math.max));
    for (final (i, p) in points.indexed) {
      final failed = plays[i].failed;
      final r = i == best ? _r + 1 : _r;
      if (failed) {
        canvas.drawCircle(p, r, Paint()..color = background);
      }
      canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = failed ? failColor : color
            ..strokeWidth = 1.5
            ..style = failed ? PaintingStyle.stroke : PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) =>
      old.plays != plays || old.color != color;
}
