/// Shared widgets and utilities for the camera and load-image OCR pages.
library;

import 'dart:typed_data';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

// Side picker on the pill tabs, shared by the camera and load-image pages.
// Reads the saved preference from Settings on first build, calls [onChanged]
// when the user switches, and persists the new value automatically.
class DetectionSideSelector extends StatelessWidget {
  final DetectionSide value;
  final ValueChanged<DetectionSide> onChanged;
  // Floating variant: no reserved band around the picker, for overlaying on
  // the camera preview / loaded image.
  final bool overlay;

  const DetectionSideSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.overlay = false,
  });

  void _onSelectionChanged(Set<DetectionSide> s) {
    final side = s.first;
    Settings.setInt(Settings.detectionSideKey, side.index);
    onChanged(side);
  }

  @override
  Widget build(BuildContext context) {
    final picker = SizedBox(
      width: 260,
      child: PillTabs<DetectionSide>(
        values: const [DetectionSide.left, DetectionSide.right],
        tabs: const [Tab(text: 'Left · 1P'), Tab(text: 'Right · 2P')],
        selected: value,
        onChanged: (side) => _onSelectionChanged({side}),
      ),
    );
    if (overlay) return Center(child: picker);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(child: picker),
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
    final pop = FloorPop.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  color: pop.riser, borderRadius: BorderRadius.circular(24)),
              child: Icon(icon, size: 40, color: pop.haze),
            ),
            const SizedBox(height: 20),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: FloorPop.display(18,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: pop.haze),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Full-screen pinch-zoomable viewer for a debug render (e.g. the ROI
// overlay). Listens to the same notifier the OCR result stream feeds, so the
// image keeps updating live while a session runs — the zoom/pan transform is
// preserved across updates, letting a region stay under inspection frame to
// frame.
class DebugImageViewer extends StatelessWidget {
  final String label;
  final ValueListenable<Uint8List?> bytes;

  const DebugImageViewer({super.key, required this.label, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label, style: const TextStyle(fontSize: 16)),
      ),
      body: ValueListenableBuilder<Uint8List?>(
        valueListenable: bytes,
        builder: (context, b, _) {
          if (b == null) {
            return const Center(
              child: Text('No image', style: TextStyle(color: Colors.white54)),
            );
          }
          return InteractiveViewer(
            maxScale: 12,
            child: Center(
              child: Image.memory(
                b,
                gaplessPlayback: true,
                fit: BoxFit.contain,
                // Nearest-neighbour so zoomed-in pixels stay crisp — the point
                // of the viewer is inspecting exact ROI/crop boundaries.
                filterQuality: FilterQuality.none,
              ),
            ),
          );
        },
      ),
    );
  }
}

// Small translucent zoom chip for overlaying on an image: hidden while
// [bytes] is null, otherwise opens [DebugImageViewer] on the same notifier.
// Shared by the camera (stopped view) and load-image pages.
class DebugZoomChip extends StatelessWidget {
  final String label;
  final ValueListenable<Uint8List?> bytes;

  const DebugZoomChip({super.key, required this.label, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: bytes,
      builder: (context, b, _) {
        if (b == null) return const SizedBox.shrink();
        return Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DebugImageViewer(label: label, bytes: bytes),
            )),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.zoom_in, size: 18, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

// One OCR reading on a riser: its label, then [child] (the value, usually
// editable) and [trailing], with a Volt bar along the bottom for how many
// frames agree on it when [confidence] is known.
class OcrFieldTile extends StatelessWidget {
  final String label;
  final Color? labelColor;
  final double? confidence;
  final Widget child;
  final Widget? trailing;

  const OcrFieldTile({
    super.key,
    required this.label,
    this.labelColor,
    this.confidence,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Container(
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(14)),
      child: Stack(fit: StackFit.expand, children: [
        Padding(
          padding: EdgeInsets.only(left: 12, right: trailing == null ? 12 : 0),
          child: Row(children: [
            Text(label,
                style: pop.label.copyWith(
                    letterSpacing: 0.7, color: labelColor ?? pop.haze)),
            const SizedBox(width: 8),
            Expanded(child: child),
            if (trailing != null) trailing!,
          ]),
        ),
        if (confidence != null) ConfidenceBar(confidence!),
      ]),
    );
  }
}

// A Volt bar along the bottom of a Stack, as wide as the share of frames
// that agree on a reading.
class ConfidenceBar extends StatelessWidget {
  final double confidence;

  const ConfidenceBar(this.confidence, {super.key});

  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        bottom: 0,
        right: 0,
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: FloorPop.eighth,
            curve: FloorPop.settle,
            widthFactor: confidence.clamp(0.0, 1.0),
            child: Container(
                height: 3, color: FloorPop.volt.withValues(alpha: 0.7)),
          ),
        ),
      );
}

// Returns the saved DetectionSide preference, defaulting to left.
DetectionSide savedDetectionSide() {
  final index = Settings.getInt(Settings.detectionSideKey);
  return index == DetectionSide.right.index
      ? DetectionSide.right
      : DetectionSide.left;
}
