import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

final _roiPaint = Paint()
  ..strokeWidth = 3.0
  ..color = Colors.red
  ..style = PaintingStyle.stroke;

final _detailsPaint = Paint()
  ..strokeWidth = 3.0
  ..color = Colors.lightGreenAccent
  ..style = PaintingStyle.stroke;

final _paragraphStyle = ui.ParagraphStyle(
  textAlign: TextAlign.left,
  fontSize: 15,
  fontWeight: ui.FontWeight.bold,
);

final _textStyle = ui.TextStyle(
  color: Colors.amber,
  shadows: [
    const Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
  ],
);

// Draws each ROI rectangle (the details ROI in green, others in red) plus its
// index label. Shared by the picker overlay and the live camera painter.
void paintRois(Canvas canvas, List<Rectangle<int>> rois, int? detailsRoiIndex) {
  for (int i = 0; i < rois.length; i++) {
    final roi = rois[i];

    final rectToDraw = Rect.fromLTWH(
      roi.left.toDouble(),
      roi.top.toDouble(),
      roi.width.toDouble(),
      roi.height.toDouble(),
    );

    final paintToUse =
        (detailsRoiIndex != null && i == detailsRoiIndex) ? _detailsPaint : _roiPaint;
    canvas.drawRect(rectToDraw, paintToUse);

    final builder = ui.ParagraphBuilder(_paragraphStyle)
      ..pushStyle(_textStyle)
      ..addText(i.toString());
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: rectToDraw.width));
    canvas.drawParagraph(paragraph, Offset(rectToDraw.right + 6, rectToDraw.top));
  }
}

// Variant of [paintRois] for the live camera overlay. Accepts pre-smoothed
// [Rect] values (doubles) to avoid integer rounding artifacts mid-animation.
void paintSmoothedRois(Canvas canvas, List<Rect> rois, int? detailsRoiIndex) {
  for (int i = 0; i < rois.length; i++) {
    final rect = rois[i];
    final paintToUse =
        (detailsRoiIndex != null && i == detailsRoiIndex)
            ? _detailsPaint
            : _roiPaint;
    canvas.drawRect(rect, paintToUse);
    final builder = ui.ParagraphBuilder(_paragraphStyle)
      ..pushStyle(_textStyle)
      ..addText(i.toString());
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(paragraph, Offset(rect.right + 6, rect.top));
  }
}

class RoiResultPainter extends CustomPainter {
  RoiResultPainter({required this.rois, this.detailsRoiIndex});

  final List<Rectangle<int>> rois;
  final int? detailsRoiIndex;

  @override
  void paint(Canvas canvas, Size size) => paintRois(canvas, rois, detailsRoiIndex);

  @override
  bool shouldRepaint(covariant RoiResultPainter oldDelegate) =>
      rois != oldDelegate.rois;
}
