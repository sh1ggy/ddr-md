/// Name: SectionBar
/// Parent: ChartScroller
/// Description: The bar over the transport while picking a snippet's section:
/// what to tap next, the section picked so far, and play/clear.
library;

import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

/// [range] as the bars it spans, e.g. "Bars 32–36".
String sectionLabel(BeatRange range, List<TimeSignature> timeSignatures) {
  final grid = BarGrid(timeSignatures);
  final from = grid.barAt(range.$1);
  final to = grid.barAt(range.$2);
  return from == to ? "Bar $from" : "Bars $from–$to";
}

class SectionBar extends StatelessWidget {
  const SectionBar({
    super.key,
    required this.range,
    required this.started,
    required this.timeSignatures,
    required this.playing,
    required this.onPlay,
    required this.onClear,
  });

  final BeatRange? range;

  /// The first row is tapped and the last isn't yet.
  final bool started;
  final List<TimeSignature> timeSignatures;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final range = this.range;
    final prompt = started
        ? "Tap the last arrow"
        : range == null
            ? "Tap the first arrow"
            : "Tap near an end to move it";
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSectionColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (range != null)
                  Text(
                    sectionLabel(range, timeSignatures),
                    style: const TextStyle(
                        color: kSectionColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                Text(
                  prompt,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13),
                ),
              ],
            ),
          ),
          if (range != null || started)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
          IconButton(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                color: range == null ? Colors.white38 : kSectionColor),
            tooltip: playing ? 'Pause' : 'Play the section',
            onPressed: range == null ? null : onPlay,
          ),
        ],
      ),
    );
  }
}
