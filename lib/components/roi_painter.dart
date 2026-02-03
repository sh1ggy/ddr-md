import 'dart:math';

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

  @override
  void paint(Canvas canvas, Size size) {
    final centerRectWidth = size.width * 0.1;
    final centerRectHeight = size.height * 0.1;

    for (int i = 0; i < rois.length; i++) {
      final roi = rois[i];
      final rectToDraw = Rect.fromLTWH(
        roi.left.toDouble(),
        roi.top.toDouble(),
        roi.width.toDouble(),
        roi.height.toDouble(),
      );
      canvas.drawRect(rectToDraw, _fillPaint);
      canvas.drawRect(rectToDraw, _paint);
    }

    // canvas.rotate(pi/2);
  }

  @override
  bool shouldRepaint(RoiResultPainter oldDelegate) {
    return rois != oldDelegate.rois;
  }
}
