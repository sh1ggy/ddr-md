import 'dart:math';

import 'package:flutter/material.dart';

class OCRResultPainter extends CustomPainter {
  OCRResultPainter({required this.roi});

  final Rectangle<int> roi;

  final _paint = Paint()
    ..strokeWidth = 3.0
    ..color = Colors.red
    ..style = PaintingStyle.stroke;

  final _fillPaint = Paint()
    ..color = Colors.red.withOpacity(0.1)
    ..style = PaintingStyle.fill;

  final _centerPaint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final centerRectWidth = size.width * 0.1;
    final centerRectHeight = size.height * 0.1;

    final centerRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: centerRectWidth,
      height: centerRectHeight,
    );
    if (roi.width <= 0 || roi.height <= 0) {
      canvas.drawRect(centerRect, _centerPaint);
      return;
    }

    final rect = Rect.fromLTWH(
      roi.left.toDouble(),
      roi.top.toDouble(),
      roi.width.toDouble(),
      roi.height.toDouble(),
    );

    canvas.drawRect(rect, _fillPaint);
    canvas.drawRect(rect, _paint);

    // canvas.rotate(pi/2);
  }

  @override
  bool shouldRepaint(OCRResultPainter oldDelegate) {
    return roi != oldDelegate.roi;
  }
}
