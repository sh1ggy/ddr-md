import 'dart:math';

import 'package:ddr_md/components/roi_painter.dart';
import 'package:flutter/material.dart';

class RoiOverlay extends StatelessWidget {
  final Widget child;
  final List<Rectangle<int>> rois;
  final int? detailsRoiIndex;

  const RoiOverlay({
    super.key,
    required this.child,
    required this.rois,
    this.detailsRoiIndex,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          RoiResultPainter(rois: rois, detailsRoiIndex: detailsRoiIndex),
      child: child,
    );
  }
}
