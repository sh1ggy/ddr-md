/// Name: ChartPreviewPage
/// Parent: SongPage (opened via the "Chart preview" button)
/// Description: Full-screen route hosting the scrolling chart renderer for one
/// song/mode/difficulty. Kept off the song page itself so its running Ticker
/// and full-height canvas only exist while the user is actually watching the
/// preview, not while scrolling the song details.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';

class ChartPreviewPage extends StatefulWidget {
  const ChartPreviewPage({
    super.key,
    required this.stepsFuture,
    required this.mode,
    required this.difficultyKey,
    required this.title,
    required this.songLength,
    required this.chartBpm,
    required this.bpms,
    required this.stops,
  });

  /// The (already in-flight) lazy load of the song's step file, shared with the
  /// song page so opening the preview doesn't re-read the asset.
  final Future<SongSteps?> stepsFuture;
  final Modes mode;
  final String difficultyKey;
  final String title;
  final double songLength;
  final int chartBpm;

  /// BPM segments and stops for this chart, in seconds (from [Chart]). Rendered
  /// as timing markers in the scroller so the preview reflects tempo shifts.
  final List<Bpm> bpms;
  final List<Stop> stops;

  @override
  State<ChartPreviewPage> createState() => _ChartPreviewPageState();
}

class _ChartPreviewPageState extends State<ChartPreviewPage> {
  bool _showFootGuide = true;

  @override
  Widget build(BuildContext context) {
    final modeLabel = widget.mode == Modes.singles ? "SP" : "DP";
    final diffColor = difficultyColor(widget.difficultyKey);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        // A difficulty-coloured accent strip under the app bar.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: diffColor),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                  fontSize: 18,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "$modeLabel · ${_pretty(widget.difficultyKey)}",
              style: TextStyle(
                  fontSize: 12,
                  color: diffColor,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showFootGuide ? "Hide foot guide" : "Show foot guide",
            onPressed: () => setState(() => _showFootGuide = !_showFootGuide),
            icon: Icon(
              _showFootGuide
                  ? Icons.directions_walk
                  : Icons.directions_walk_outlined,
              color: _showFootGuide ? diffColor : Colors.blueGrey,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<SongSteps?>(
          future: widget.stepsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final steps = snapshot.data?.chartFor(widget.mode, widget.difficultyKey);
            if (steps == null || steps.notes.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "No chart data available for this difficulty.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(10),
              child: ChartScroller(
                key: ValueKey(
                    "${widget.title}-${widget.mode.name}-${widget.difficultyKey}"),
                steps: steps,
                mode: widget.mode,
                songLength: widget.songLength,
                chartBpm: widget.chartBpm,
                bpms: widget.bpms,
                stops: widget.stops,
                showFootGuide: _showFootGuide,
              ),
            );
          },
        ),
      ),
    );
  }
}

String _pretty(String difficultyKey) =>
    difficultyKey.isEmpty ? "" : difficultyKey[0].toUpperCase() + difficultyKey.substring(1);
