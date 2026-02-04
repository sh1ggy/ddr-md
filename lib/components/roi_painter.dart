import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class RoiResultPainter extends CustomPainter {
  RoiResultPainter({required this.rois});

  final List<Rectangle<int>> rois;

  final _paint = Paint()
    ..strokeWidth = 3.0
    ..color = Colors.red
    ..style = PaintingStyle.stroke;

  final _fillPaint = Paint()
    ..color = Colors.red.withOpacity(0.1)
    ..style = PaintingStyle.fill;

  final paragraphStyle = ui.ParagraphStyle(
    textAlign: TextAlign.left,
    fontSize: 15,
    fontWeight: ui.FontWeight.bold,
  );

  final textStyle = ui.TextStyle(
    color: Colors.amber,
    shadows: [
      const Shadow(
        color: Colors.black,
        offset: Offset(1, 1),
        blurRadius: 2,
      ),
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < rois.length; i++) {
      final roi = rois[i];

      final rectToDraw = Rect.fromLTWH(
        roi.left.toDouble(),
        roi.top.toDouble(),
        roi.width.toDouble(),
        roi.height.toDouble(),
      );

      // Draw rect + fill
      canvas.drawRect(rectToDraw, _fillPaint);
      canvas.drawRect(rectToDraw, _paint);

      final builder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText(i.toString());

      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: rectToDraw.width));

      final offset = Offset(rectToDraw.right + 6, rectToDraw.top);
      canvas.drawParagraph(paragraph, offset);
    }
  }

  @override
  bool shouldRepaint(covariant RoiResultPainter oldDelegate) =>
      rois != oldDelegate.rois;
}
