/// Name: DensityScrubBar
/// Parent: ChartScroller
/// Description: The transport's scrub bar and its note-density minimap
/// painter. Split out of chart_scroller.dart; it takes the prebuilt buckets
/// and a playhead listenable, so it neither reads nor mutates scroller state.
library;

import 'dart:ui' as ui;

import 'chart_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A scrub bar whose track is a note-density minimap of the whole chart (busy
/// sections show taller bars), with a played/unplayed split and a draggable
/// playhead. Tap or drag anywhere to seek. [onSeek] is 0..1. The needle rides
/// [playhead] directly (via the painter's repaint listenable) so seeking and
/// playback never rebuild this widget.
class DensityScrubBar extends StatelessWidget {
  const DensityScrubBar({
    super.key,
    required this.buckets,
    required this.playhead,
    required this.endSecond,
    required this.accent,
    required this.bpmFractions,
    required this.stopFractions,
    required this.onSeek,
  });

  final List<MinimapBucket> buckets;
  final ValueListenable<double> playhead;
  final double endSecond;
  final Color accent;

  /// 0..1 positions of BPM-change and stop markers along the track.
  final List<double> bpmFractions;
  final List<double> stopFractions;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      void seekAt(double dx) =>
          onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            height: 40,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DensityPainter(
                  buckets: buckets,
                  playhead: playhead,
                  endSecond: endSecond,
                  accent: accent,
                  bpmFractions: bpmFractions,
                  stopFractions: stopFractions,
                ),
                size: Size.infinite,
                willChange: true,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _DensityPainter extends CustomPainter {
  _DensityPainter({
    required this.buckets,
    required this.playhead,
    required this.endSecond,
    required this.accent,
    required this.bpmFractions,
    required this.stopFractions,
  }) : super(repaint: playhead);

  final List<MinimapBucket> buckets;
  final ValueListenable<double> playhead;
  final double endSecond;
  final Color accent;
  final List<double> bpmFractions;
  final List<double> stopFractions;

  // The track (bars, hold underlay, shock and timing ticks) is static per
  // layout: record it once into two pictures — played styling and unplayed
  // styling — and per frame just replay each clipped at the needle. That
  // reduces the per-frame cost from ~200 buckets × several Paint allocations
  // to two drawPicture calls plus the needle.
  ui.Picture? _playedPic;
  ui.Picture? _unplayedPic;
  Size? _picSize;

  ui.Picture _recordTrack(Size size, {required bool played}) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final midY = size.height / 2;
    final maxBar = size.height * 0.42;
    final barW = size.width / buckets.length;
    final paint = Paint();
    final holdColor = const Color(0xFF39C46B)
        .withValues(alpha: played ? 0.36 : 0.18);
    final shockColor = const Color(0xFF79E7FF)
        .withValues(alpha: played ? 0.95 : 0.55);
    for (int i = 0; i < buckets.length; i++) {
      final x = i * barW;
      final bucket = buckets[i];
      // Minimum stub so silent gaps still read as a track.
      final h = (0.10 + 0.90 * bucket.level) * maxBar;
      final rect = Rect.fromLTWH(x, midY - h, barW + 0.6, h * 2);
      if (bucket.holdLevel > 0) {
        final holdH = (0.16 + 0.34 * bucket.holdLevel) * size.height;
        final holdRect = Rect.fromLTWH(
          rect.left,
          midY - holdH / 2,
          rect.width,
          holdH,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(holdRect, const Radius.circular(1.2)),
          paint..color = holdColor,
        );
      }
      if (bucket.segments.isEmpty) {
        canvas.drawRect(
          rect,
          paint..color = played ? accent : accent.withValues(alpha: 0.28),
        );
      } else {
        double top = rect.top;
        for (final segment in bucket.segments) {
          final segH = rect.height * segment.weight;
          final segRect = Rect.fromLTWH(rect.left, top, rect.width, segH);
          canvas.drawRect(
            segRect,
            paint
              ..color = played
                  ? segment.color
                  : segment.color.withValues(alpha: 0.34),
          );
          top += segH;
        }
      }
      if (bucket.hasShock) {
        final shockRect = Rect.fromLTWH(
          rect.left,
          rect.top - 2,
          rect.width,
          4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(shockRect, const Radius.circular(1.2)),
          paint..color = shockColor,
        );
      }
    }

    // Timing ticks: stops along the bottom edge, BPM changes along the top, so
    // both are locatable when seeking without colliding with each other. The
    // same colour in both variants; baking them into each picture keeps them
    // continuous across the needle's clip seam.
    void drawTicks(List<double> fractions, Color color, bool atTop) {
      final tickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5;
      final y0 = atTop ? 0.0 : size.height - 6;
      final y1 = atTop ? 6.0 : size.height;
      for (final f in fractions) {
        final x = (size.width * f).clamp(0.0, size.width).toDouble();
        canvas.drawLine(Offset(x, y0), Offset(x, y1), tickPaint);
      }
    }

    drawTicks(
        bpmFractions, const Color(0xFF8AB4FF).withValues(alpha: 0.9), true);
    drawTicks(
        stopFractions, const Color(0xFFFFB454).withValues(alpha: 0.9), false);
    return rec.endRecording();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final progress =
        endSecond <= 0 ? 0.0 : (playhead.value / endSecond).clamp(0.0, 1.0);
    final playedX = (size.width * progress).clamp(0.0, size.width).toDouble();

    if (buckets.isEmpty) {
      // Fallback: a plain rounded track.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, midY - 2.5, size.width, 5),
              const Radius.circular(3)),
          Paint()..color = Colors.white24);
    } else {
      if (_picSize != size) {
        _playedPic = _recordTrack(size, played: true);
        _unplayedPic = _recordTrack(size, played: false);
        _picSize = size;
      }
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, -4, playedX, size.height + 8));
      canvas.drawPicture(_playedPic!);
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          playedX, -4, size.width - playedX, size.height + 8));
      canvas.drawPicture(_unplayedPic!);
      canvas.restore();
    }

    // Playhead: vertical needle plus a layered knob for stronger visibility.
    canvas.drawRect(
      Rect.fromLTWH(playedX - 1, 0, 2, size.height),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      10,
      Paint()..color = accent.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      6,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      2.4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_DensityPainter old) =>
      old.buckets != buckets ||
      old.endSecond != endSecond ||
      old.accent != accent ||
      old.bpmFractions != bpmFractions ||
      old.stopFractions != stopFractions;
}
