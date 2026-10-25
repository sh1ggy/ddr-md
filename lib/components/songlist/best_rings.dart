/// Name: BestRings
/// Parent: DifficultyListPage
/// Description: The listed charts' bests as three nested rings, in the
/// cabinet's order from the outside in: grade, lamp, flare. Each fills
/// clockwise from the top, best tier first, in the stats page's colours;
/// played charts without one follow in grey, and the rest is the unplayed.
library;

import 'dart:math' as math;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

// [rainbow] sweeps along the arc in place of its colour.
typedef _Arc = ({double share, Color color, List<Color>? rainbow});

const _kNone = Color(0xFF757575);

class BestRings extends StatelessWidget {
  const BestRings(this.bests, {super.key, this.size = 30});

  /// One per listed chart, null where it hasn't been played.
  final List<ChartBest?> bests;
  final double size;

  List<_Arc> _arcs<T>(
      List<T> tiers, T? Function(ChartBest) of, Color Function(T) color,
      [List<Color>? Function(T)? rainbow]) {
    final counts = <T, int>{};
    var none = 0;
    for (final b in bests) {
      if (b == null) continue;
      if (of(b) case final tier?) {
        counts[tier] = (counts[tier] ?? 0) + 1;
      } else {
        none++;
      }
    }
    return [
      for (final t in tiers)
        if (counts[t] case final n?)
          (share: n / bests.length, color: color(t), rainbow: rainbow?.call(t)),
      if (none > 0) (share: none / bests.length, color: _kNone, rainbow: null),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (bests.isEmpty) return const SizedBox.shrink();
    final rings = [
      _arcs(Grade.values, (b) => b.grade, gradeColor),
      _arcs(ClearLamp.values.reversed.toList(), (b) => b.lamp,
          (l) => kLampColors[l]!),
      _arcs(kFlareRanks.reversed.toList(), (b) => b.flare, flareColor,
          (r) => r == 'EX' ? kFlareExColors : null),
    ];
    return TweenAnimationBuilder<double>(
      // Sweeps in afresh whenever the filter lands on a different mix.
      key: ValueKey(Object.hashAll([
        for (final ring in rings)
          for (final a in ring) Object.hash(a.share, a.color),
      ])),
      tween: Tween(begin: 0, end: 1),
      duration: FloorPop.beat * 2,
      curve: FloorPop.settle,
      builder: (context, t, _) => CustomPaint(
        size: Size.square(size),
        painter: _RingsPainter(
            rings, t, Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings, this.t, this.track);

  final List<List<_Arc>> rings;
  final double t;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide / 10;
    final center = size.center(Offset.zero);
    // Angles from here on run clockwise from the top.
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 2);
    for (var i = 0; i < rings.length; i++) {
      final radius = size.shortestSide / 2 - stroke * (0.5 + i * 1.4);
      final rect = Rect.fromCircle(center: Offset.zero, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawCircle(Offset.zero, radius, paint..color = track);
      var start = 0.0;
      for (final arc in rings[i]) {
        final sweep = arc.share * 2 * math.pi * t;
        if (sweep <= 0) continue;
        paint
          ..color = arc.color
          ..shader = arc.rainbow == null
              ? null
              : SweepGradient(
                      colors: arc.rainbow!,
                      startAngle: start,
                      endAngle: start + sweep)
                  .createShader(rect);
        canvas.drawArc(rect, start, sweep, false, paint);
        start += sweep;
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t || old.rings != rings || old.track != track;
}
