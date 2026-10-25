/// Name: FlareCard
/// Parent: SongListItem, ArcadeGridTile
/// Description: How the song list marks the player's best on a chart: a card
/// in the chart's flare colours, the way the cabinet's song select tints it
/// (a frame over a darker back), and badges for what's on it that keep their
/// place, pressed in where there's nothing to show.
library;

import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
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

/// A badge on a card: raised when it holds something, pressed in when it's
/// empty, so a missing grade, flare or lamp still keeps its place.
class CardBadge extends StatelessWidget {
  const CardBadge(
      {super.key, this.child, required this.width, required this.height});

  final Widget? child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(6);
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: child == null
          ? BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0x73000000), Color(0x33000000)]
                    : const [Color(0x1F000000), Color(0x0A000000)],
              ),
            )
          : BoxDecoration(
              borderRadius: radius,
              color: dark ? const Color(0x47000000) : const Color(0xBFFFFFFF),
              border: Border.all(
                  color:
                      dark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
                  width: 0.5),
            ),
      child: child,
    );
  }
}

/// A chart's grade, flare and clear lamp as a row of badges, each art drawn
/// [ink] tall (its visible part, not the image's margin), so the three read at
/// one size.
class ChartBestBadges extends StatelessWidget {
  const ChartBestBadges(this.best,
      {super.key, required this.ink, required this.height, this.gap = 6});

  final ChartBest? best;
  final double ink;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final grade = best?.grade, flare = best?.flare;
    // Each badge fits the widest drawn part of its kind of art: grades are
    // about 1.6:1, flare badges at most 1.3:1, and the plain CLEAR lamp the
    // widest of the lamps at 4:1.
    Widget badge(String? art, double aspect) => CardBadge(
          width: ink * aspect + 8,
          height: height,
          child: art == null
              ? null
              : OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Image.asset(art, height: ink / _drawnHeight(art))),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      badge(grade == null ? null : gradeIcon(grade), 1.65),
      SizedBox(width: gap),
      badge(flare == null ? null : flareRankIcon(flare), 1.3),
      SizedBox(width: gap),
      badge(clearLampIcon(best?.lamp), 4.05),
    ]);
  }

  // How much of an art's height is drawn, the rest being transparent margin.
  static double _drawnHeight(String art) => art.contains('/rank_')
      ? 0.74
      : art == clearIcon
          ? 0.67
          : 1;
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
