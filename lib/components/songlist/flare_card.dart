/// Name: FlareCard
/// Parent: SongListItem, ArcadeGridTile
/// Description: How the song list marks the player's best on a chart: a card
/// in the chart's flare colours, the way the cabinet's song select tints it
/// (a frame over a darker back), and [ArtBadge]s for what's on it.
library;

import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show formatScore, kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/theme.dart' show FloorPop;
import 'package:flutter/material.dart';

/// The card's back for [flare]. In the light theme it's the frame's colour
/// washed out instead, so dark text still reads.
BoxDecoration flareCardBack(BuildContext context, String? flare,
    {required double radius}) {
  final pop = FloorPop.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final borderRadius = BorderRadius.circular(radius);
  if (flare == null) {
    return BoxDecoration(color: pop.riser, borderRadius: borderRadius);
  }
  if (flare == 'EX') {
    return BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(colors: [
          for (final c in kFlareExColors)
            Color.lerp(pop.stage, c, dark ? 0.22 : 0.18)!
        ]));
  }
  final colors = kFlareCardColors[kFlareRanks.indexOf(flare)];
  return BoxDecoration(
      borderRadius: borderRadius,
      color: dark ? colors.back : Color.lerp(pop.stage, colors.frame, 0.15));
}

/// A flare rank's frame round a chart's card; EX's runs through the rainbow.
class FlareFrame extends CustomPainter {
  FlareFrame(this.rank, {required this.radius});

  final String rank;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.75);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (rank == 'EX') {
      paint.shader =
          SweepGradient(colors: [...kFlareExColors, kFlareExColors.first])
              .createShader(rect);
    } else {
      paint.color = kFlareCardColors[kFlareRanks.indexOf(rank)].frame;
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
  }

  @override
  bool shouldRepaint(FlareFrame old) =>
      old.rank != rank || old.radius != radius;
}

/// A chart's flare, grade and clear lamp as a row of badges, the lamp last
/// since it's the widest, each art drawn [ink] tall (its visible part, not the
/// image's margin), so the three read at one size. With [score], the best
/// score leads the row.
class ChartBestBadges extends StatelessWidget {
  const ChartBestBadges(this.best,
      {super.key,
      required this.ink,
      required this.height,
      this.gap = 6,
      this.score = false});

  final ChartBest? best;
  final double ink;
  final double height;
  final double gap;
  final bool score;

  @override
  Widget build(BuildContext context) {
    final grade = best?.grade, flare = best?.flare;
    Widget badge(String? art, double aspect) =>
        ArtBadge(art, aspect: aspect, ink: ink, height: height);
    final top = best?.score;
    // Even-width digits, so every six-digit score is one width.
    final style = FloorPop.readout(ink + 2)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (score) ...[
        // A six-digit score, hidden, sets the slot so the badges line up down
        // the list; a 1,000,000 narrows to fit it rather than widening every
        // row's slot.
        Stack(children: [
          Visibility.maintain(
              visible: false, child: Text(formatScore(999999), style: style)),
          if (top != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatScore(top), style: style),
              ),
            ),
        ]),
        SizedBox(width: gap + 2),
      ],
      badge(flare == null ? null : flareRankIcon(flare), kFlareAspect),
      SizedBox(width: gap),
      badge(grade == null ? null : gradeIcon(grade), kGradeAspect),
      SizedBox(width: gap),
      badge(clearLampIcon(best?.lamp), kLampAspect),
    ]);
  }
}

/// The darker band along a card's bottom that carries its badges, like the
/// band across the foot of the cabinet's cards.
class CardFooter extends StatelessWidget {
  const CardFooter({super.key, required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0x40000000)
            : const Color(0x0D000000),
        child: Padding(padding: padding, child: child),
      );
}
