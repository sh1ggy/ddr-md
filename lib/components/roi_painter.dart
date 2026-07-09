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

final _textStyle = ui.TextStyle(color: Colors.amber);

final _labelBgPaint = Paint()..color = Colors.black54;

// The camera painter repaints every ticker frame; caching the laid-out
// paragraphs means each frame draws the exact same object, so the labels
// render identically instead of occasionally losing their fill color the way
// per-frame shadowed paragraphs did.
final _labelCache = <int, ui.Paragraph>{};

ui.Paragraph _labelFor(int i) => _labelCache.putIfAbsent(i, () {
      final builder = ui.ParagraphBuilder(_paragraphStyle)
        ..pushStyle(_textStyle)
        ..addText(i.toString());
      return builder.build()
        ..layout(const ui.ParagraphConstraints(width: 60));
    });

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

    final label = _labelFor(i);
    final labelOffset = Offset(rectToDraw.right + 6, rectToDraw.top);
    canvas.drawRect(
      Rect.fromLTWH(labelOffset.dx - 3, labelOffset.dy - 1,
          label.longestLine + 6, label.height + 2),
      _labelBgPaint,
    );
    canvas.drawParagraph(label, labelOffset);
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
