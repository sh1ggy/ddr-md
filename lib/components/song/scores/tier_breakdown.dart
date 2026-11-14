/// Name: TierBreakdown
/// Parent: BestStrip, ScoreOverviewPage
/// Description: A measure's tiers (lamps, grades or flare) as one bar, each
/// tier a band in its colour, and every tier's badge with its count, three
/// to a row so every measure's badges are the same width.
library;

import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

/// A tier and how many charts hold it. [rainbow] sweeps along its band in
/// place of [color]; [label] stands in where there's no [art].
typedef TierCount = ({
  int count,
  Color color,
  List<Color>? rainbow,
  String? art,
  String label,
});

/// [tiers] as bands left to right, out of [total] charts on a [track], only
/// [fill] of the way drawn, for an entrance.
class TierBarPainter extends CustomPainter {
  TierBarPainter(this.tiers, this.total, this.track, {this.fill = 1});

  final List<TierCount> tiers;
  final int total;
  final Color track;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    canvas.clipRRect(
        RRect.fromRectAndRadius(whole, Radius.circular(size.height / 2)));
    canvas.drawRect(whole, Paint()..color = track);
    if (total == 0) return;
    final unit = size.width / total * fill;
    var x = 0.0;
    for (final t in tiers) {
      final band = Rect.fromLTWH(x, 0, t.count * unit, size.height);
      canvas.drawRect(
          band,
          Paint()
            ..color = t.color
            ..shader = t.rainbow == null
                ? null
                : LinearGradient(colors: t.rainbow!).createShader(band));
      x = band.right;
    }
  }

  @override
  bool shouldRepaint(TierBarPainter old) =>
      old.tiers != tiers ||
      old.total != total ||
      old.track != track ||
      old.fill != fill;
}

/// Every tier's badge and count, empty ones dimmed, [columns] to a row.
class TierGrid extends StatelessWidget {
  const TierGrid(this.tiers,
      {super.key, required this.aspect, this.columns = 3});

  final List<TierCount> tiers;

  /// The widest drawn part of the tiers' art: [kLampAspect] and so on.
  final double aspect;
  final int columns;

  static const _height = 28.0, _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final t in tiers)
            Opacity(
              opacity: t.count > 0 ? 1 : 0.3,
              child: ArtTile(t.art,
                  aspect: aspect,
                  ink: 12,
                  width: (box.maxWidth - (columns - 1) * _gap) / columns,
                  height: _height,
                  color: t.color,
                  label: Text(t.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: pop.haze)),
                  trailing: Text('${t.count}', style: FloorPop.readout(15))),
            ),
        ],
      ),
    );
  }
}
