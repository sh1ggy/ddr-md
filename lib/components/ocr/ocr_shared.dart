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

// Muted icon + title (+ optional subtitle) empty state shared by the OCR
// pages: prompts ("pick an image", "start OCR") and no-result messages.
// Centers itself within whatever space the parent gives it.
class OcrEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const OcrEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final mutedColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: mutedColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: mutedColor,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: mutedColor),
              ),
            ],
          ],
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
