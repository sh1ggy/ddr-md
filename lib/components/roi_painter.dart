import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class RoiResultPainter extends CustomPainter {
  RoiResultPainter({required this.rois, this.detailsRoiIndex});

  final List<Rectangle<int>> rois;
  final int? detailsRoiIndex;

  final _paint = Paint()
    ..strokeWidth = 3.0
    ..color = Colors.red
    ..style = PaintingStyle.stroke;

  final _detailsPaint = Paint()
    ..strokeWidth = 3.0
    ..color = Colors.lightGreenAccent
    ..style = PaintingStyle.stroke;

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

      final paintToUse = (detailsRoiIndex != null && i == detailsRoiIndex)
          ? _detailsPaint
          : _paint;

      // Draw rect + fill
      canvas.drawRect(rectToDraw, paintToUse);

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
