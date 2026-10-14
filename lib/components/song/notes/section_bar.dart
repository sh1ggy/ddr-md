/// Name: SectionBar
/// Parent: ChartScroller
/// Description: The bar over the transport while picking a snippet's section:
/// minimal Preview and Add actions.
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
  const SectionBar(
      {super.key,
      required this.range,
      required this.playing,
      required this.onPlay,
      this.onSave});
  final BeatRange? range;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.75),
                    side: const BorderSide(color: Colors.white38),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: range == null ? null : onPlay,
                icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(playing ? 'Pause' : 'Preview'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: kSectionColor,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: range == null ? null : onSave,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'))),
      ]);
}
