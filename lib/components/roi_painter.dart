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

final _projectedQuadPaint = Paint()
  ..strokeWidth = 3.0
  ..color = Colors.yellow
  ..style = PaintingStyle.stroke;

// Draws the 4-corner quad the inter-frame tracker projected forward when the
// HSV/Tesseract detector missed. Dashed yellow so it visually distinguishes
// "tracked" from the solid green "freshly detected" Details rect.
void paintProjectedQuad(Canvas canvas, List<Offset> quad) {
  if (quad.length != 4) return;
  const dashLen = 12.0;
  const gapLen = 8.0;
  for (int i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];
    final segLen = (b - a).distance;
    if (segLen <= 0) continue;
    final dir = (b - a) / segLen;
    double drawn = 0;
    while (drawn < segLen) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dashLen).clamp(0, segLen).toDouble();
      canvas.drawLine(start, end, _projectedQuadPaint);
      drawn += dashLen + gapLen;
    }
  }
}

class ProjectedQuadPainter extends CustomPainter {
  ProjectedQuadPainter({required this.quad}) : super(repaint: quad);

  final ValueNotifier<List<Offset>?> quad;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad.value;
    if (q == null) return;
    paintProjectedQuad(canvas, q);
  }

  @override
  bool shouldRepaint(covariant ProjectedQuadPainter oldDelegate) => false;
}
