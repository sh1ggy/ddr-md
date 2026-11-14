/// Name: ScoreHistorySheet
/// Parent: ScoresTab
/// Description: Bottom sheet opened from a chart's best. Pick a chart, then
/// its best over time on true dates against the grades, and every synced
/// play, newest first.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show formatScore, kInGameDifficultyColors;
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

/// One chart's best with its level and synced plays (oldest first, scored).
typedef ChartHistory = ({
  ScoreRecord record,
  int? level,
  List<RecentPlay> plays
});

Future<void> showScoreHistory(
        BuildContext context, List<ChartHistory> charts, int initial) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
          heightFactor: 0.85,
          child: ScoreHistorySheet(charts: charts, initial: initial)),
    );

class ScoreHistorySheet extends StatefulWidget {
  const ScoreHistorySheet(
      {super.key, required this.charts, required this.initial});

  final List<ChartHistory> charts;
  final int initial;

  @override
  State<ScoreHistorySheet> createState() => _ScoreHistorySheetState();
}

class _ScoreHistorySheetState extends State<ScoreHistorySheet> {
  late int _picked = widget.initial;

  @override
  Widget build(BuildContext context) {
    final fp = FloorPop.of(context);
    final chart = widget.charts[_picked];
    final plays = chart.plays;
    final color = kInGameDifficultyColors[chart.record.difficulty]!;
    final best = plays.where((p) => !p.failed).fold<RecentPlay?>(
        null, (b, p) => b == null || p.score! > b.score! ? p : b);
    // A play that beat every pass before it.
    final newBest = <RecentPlay>{};
    var top = -1;
    for (final p in plays) {
      if (!p.failed && p.score! > top) {
        top = p.score!;
        newBest.add(p);
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (widget.charts.length > 1)
          Row(children: [
            for (final (i, c) in widget.charts.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                  child: _ChartTab(
                      chart: c,
                      selected: i == _picked,
                      onTap: () => setState(() => _picked = i))),
            ],
          ]),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ScoreBadges(
            score: chart.record.score ?? 0,
            lampArt: clearLampIcon(chart.record.clearLamp),
            flare: chart.record.flareRank,
          ),
        ),
        if (plays.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: _HistoryPlot(
                plays: plays, newBest: newBest, color: color, fp: fp),
          ),
          const SizedBox(height: 8),
          for (final p in plays.reversed)
            _PlayRow(
                play: p,
                best: best?.score,
                isNewBest: newBest.contains(p) && !identical(p, plays.first),
                isBest: identical(p, best),
                fp: fp),
        ],
      ],
    );
  }
}

class _ChartTab extends StatelessWidget {
  const _ChartTab(
      {required this.chart, required this.selected, required this.onTap});

  final ChartHistory chart;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fp = FloorPop.of(context);
    return Material(
      color: selected ? fp.riser : Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: selected ? FloorPop.volt : fp.line,
              width: selected ? 1.5 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                DifficultyLabel(difficulty: chart.record.difficulty),
                if (chart.level != null) ...[
                  const SizedBox(width: 6),
                  LevelNumber(
                      level: chart.level!, difficulty: chart.record.difficulty),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String _date(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final l = d.toLocal();
  return '${months[l.month - 1]} ${l.day}';
}

class _PlayRow extends StatelessWidget {
  const _PlayRow(
      {required this.play,
      required this.best,
      required this.isNewBest,
      required this.isBest,
      required this.fp});

  final RecentPlay play;
  final int? best;
  final bool isNewBest, isBest;
  final FloorPop fp;

  @override
  Widget build(BuildContext context) {
    final score = play.score!;
    return Container(
      height: 40,
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: fp.line))),
      child: Row(children: [
        SizedBox(
            width: 56,
            child: Text(_date(play.playedAt),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fp.haze))),
        SizedBox(
          width: 96,
          child: Text(formatScore(score),
              textAlign: TextAlign.right,
              style: FloorPop.readout(16,
                  color: play.failed
                      ? FloorPop.coral
                      : isBest
                          ? fp.sunText
                          : null)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
              play.failed || isBest || best == null
                  ? ''
                  : '−${formatScore(best! - score)}',
              style: FloorPop.readout(12, color: fp.haze)),
        ),
        if (play.failed)
          const Icon(Icons.close_rounded, size: 18, color: FloorPop.coral)
        else if (isNewBest)
          const Icon(Icons.star_rounded, size: 18, color: FloorPop.sun),
      ]),
    );
  }
}

/// The running best as a step line over true dates, each play a dot. Grade
/// floors from 900k up are banded and their art sits at the right edge.
class _HistoryPlot extends StatelessWidget {
  const _HistoryPlot(
      {required this.plays,
      required this.newBest,
      required this.color,
      required this.fp});

  final List<RecentPlay> plays;
  final Set<RecentPlay> newBest;
  final Color color;
  final FloorPop fp;

  static const _grades = [Grade.aaa, Grade.aaPlus, Grade.aa];

  @override
  Widget build(BuildContext context) {
    final passed = [
      for (final p in plays)
        if (!p.failed) p.score!
    ];
    // Down to AA, or 50k below the lowest pass when that is lower.
    final low = passed.isEmpty ? 900000 : passed.reduce(math.min);
    final floor = math.min(900000, (low - 1) ~/ 50000 * 50000);
    return LayoutBuilder(builder: (context, box) {
      const plotH = 150.0, artH = 14.0;
      double y(int v) =>
          plotH * (1 - ((v - floor) / (1000000 - floor)).clamp(0.0, 1.0));
      return Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PlotPainter(
                plays: plays,
                newBest: newBest,
                color: color,
                fp: fp,
                y: y,
                plotH: plotH),
          ),
        ),
        for (final g in _grades)
          if (g.minScore >= floor)
            Positioned(
              right: 0,
              top: math.max(0, y(g.minScore) - artH - 1),
              child: ArtBadge(gradeIcon(g),
                  aspect: kGradeAspect, ink: 10, height: artH),
            ),
        Positioned(
            left: 0,
            bottom: 0,
            child: Text(_date(plays.first.playedAt),
                style: TextStyle(fontSize: 10, color: fp.haze))),
      ]);
    });
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter(
      {required this.plays,
      required this.newBest,
      required this.color,
      required this.fp,
      required this.y,
      required this.plotH});

  final List<RecentPlay> plays;
  final Set<RecentPlay> newBest;
  final Color color;
  final FloorPop fp;
  final double Function(int) y;
  final double plotH;

  @override
  void paint(Canvas canvas, Size size) {
    // Bands between grade floors: AAA tinted Sun, the rest alternating Riser.
    final aaa = y(Grade.aaa.minScore), aaPlus = y(Grade.aaPlus.minScore);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, aaa),
        Paint()..color = FloorPop.sun.withValues(alpha: 0.08));
    canvas.drawRect(Rect.fromLTRB(0, aaa, size.width, aaPlus),
        Paint()..color = fp.riser.withValues(alpha: 0.6));
    canvas.drawLine(
        Offset(0, plotH), Offset(size.width, plotH), Paint()..color = fp.line);

    // True dates from the first play to now, at least two weeks wide; the
    // grade art keeps the right edge.
    final t0 = plays.first.playedAt.millisecondsSinceEpoch.toDouble();
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final span = math.max(now - t0, const Duration(days: 14).inMilliseconds);
    final w = size.width - 40;
    double x(RecentPlay p) =>
        6 + w * (p.playedAt.millisecondsSinceEpoch - t0) / span;

    for (final p in plays) {
      final c = Offset(x(p), p.failed ? plotH - 4 : y(p.score!));
      if (p.failed) {
        canvas.drawCircle(c, 4, Paint()..color = fp.stage);
        canvas.drawCircle(
            c,
            4,
            Paint()
              ..color = FloorPop.coral
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      } else {
        canvas.drawCircle(c, 4, Paint()..color = color);
      }
    }

    final step = Path();
    double? lastY;
    for (final p in newBest) {
      final px = x(p), py = y(p.score!);
      if (lastY == null) {
        step.moveTo(px, py);
      } else {
        step
          ..lineTo(px, lastY)
          ..lineTo(px, py);
      }
      lastY = py;
    }
    if (lastY != null) {
      step.lineTo(6 + w * (now - t0) / span, lastY);
      canvas.drawPath(
          step,
          Paint()
            ..color = FloorPop.sun
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);
      for (final p in newBest) {
        canvas.drawCircle(
            Offset(x(p), y(p.score!)), 5, Paint()..color = FloorPop.sun);
      }
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.plays != plays || old.color != color;
}
