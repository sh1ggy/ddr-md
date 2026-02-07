import 'dart:math';

import 'package:ddr_md/components/roi_painter.dart';
import 'package:flutter/material.dart';

class RoiOverlay extends StatelessWidget {
  final Widget child;
  final List<Rectangle<int>> rois;

  const RoiOverlay({
    super.key,
    required this.child,
    required this.rois,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: RoiResultPainter(rois: rois),
      child: child,
    );
  }
}
