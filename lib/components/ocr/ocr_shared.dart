/// Shared widgets and utilities for the camera and load-image OCR pages.
library;

import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';

// Side-selector SegmentedButton shared by the camera and load-image pages.
// Reads the saved preference from Settings on first build, calls [onChanged]
// when the user switches, and persists the new value automatically.
class DetectionSideSelector extends StatelessWidget {
  final DetectionSide value;
  final ValueChanged<DetectionSide> onChanged;

  const DetectionSideSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  void _onSelectionChanged(Set<DetectionSide> s) {
    final side = s.first;
    Settings.setInt(Settings.detectionSideKey, side.index);
    onChanged(side);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: SegmentedButton<DetectionSide>(
          segments: const [
            ButtonSegment(
                value: DetectionSide.left, label: Text('Left (1P)')),
            ButtonSegment(
                value: DetectionSide.right, label: Text('Right (2P)')),
          ],
          selected: {value},
          onSelectionChanged: _onSelectionChanged,
        ),
      ),
    );
  }
}

// Returns the saved DetectionSide preference, defaulting to left.
DetectionSide savedDetectionSide() {
  final index = Settings.getInt(Settings.detectionSideKey);
  return index == DetectionSide.right.index
      ? DetectionSide.right
      : DetectionSide.left;
}
