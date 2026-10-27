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
/// image's margin), so the three read at one size.
class ChartBestBadges extends StatelessWidget {
  const ChartBestBadges(this.best,
      {super.key, required this.ink, required this.height, this.gap = 6});

  final ChartBest? best;
  final double ink;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final flare = best?.flare;
    Widget badge(String? art, double aspect) =>
        ArtBadge(art, aspect: aspect, ink: ink, height: height);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      badge(flare == null ? null : flareRankIcon(flare), kFlareAspect),
      SizedBox(width: gap),
      badge(best?.grade == null ? null : gradeIcon(best!.grade!), kGradeAspect),
      SizedBox(width: gap),
      badge(clearLampIcon(best?.lamp), kLampAspect),
    ]);
  }
}

/// A chart's best score in a darker tab cut into a card footer's right end,
/// its last three digits small and muted so the leading ones carry the read.
/// Nothing when the chart has no score.
class BestScore extends StatelessWidget {
  const BestScore(this.best, {super.key});

  final ChartBest? best;

  @override
  Widget build(BuildContext context) {
    final top = best?.score;
    if (top == null) return const SizedBox.shrink();
    final text = formatScore(top);
    final split = text.lastIndexOf(',');
    const figures = [FontFeature.tabularFigures()];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0x40000000)
            : const Color(0x0D000000),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: text.substring(0, split),
                style: FloorPop.readout(17).copyWith(fontFeatures: figures)),
            TextSpan(
                text: text.substring(split),
                style: FloorPop.readout(12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)
                    .copyWith(fontFeatures: figures)),
          ])),
        ),
      ),
    );
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
