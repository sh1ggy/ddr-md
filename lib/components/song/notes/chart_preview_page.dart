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
import 'package:flutter/services.dart';

class ChartPreviewPage extends StatefulWidget {
  const ChartPreviewPage({
    super.key,
    required this.stepsFuture,
    required this.mode,
    required this.difficultyKey,
    required this.difficultyLevel,
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

  /// The chart's meter/level number (e.g. 14), shown next to the difficulty
  /// name in the header. Null when the song data has no level for this key.
  final int? difficultyLevel;
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
  bool _showFootGuide = false;

  @override
  Widget build(BuildContext context) {
    final diffColor = difficultyColor(widget.difficultyKey);
    // Edge-to-edge: the field owns the whole screen (including behind the status
    // bar) and the controls float over it, so no AppBar / SafeArea chrome here.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0E),
        body: FutureBuilder<SongSteps?>(
          future: widget.stepsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final steps = snapshot.data?.chartFor(widget.mode, widget.difficultyKey);
            if (steps == null || steps.notes.isEmpty) {
              return Stack(
                children: [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "No chart data available for this difficulty.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  // Still offer a way back when there's nothing to show.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.blueGrey),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ChartScroller(
              key: ValueKey(
                  "${widget.title}-${widget.mode.name}-${widget.difficultyKey}"),
              steps: steps,
              mode: widget.mode,
              songLength: widget.songLength,
              chartBpm: widget.chartBpm,
              bpms: widget.bpms,
              stops: widget.stops,
              showFootGuide: _showFootGuide,
              headerBuilder: (context) => _buildHeader(context, diffColor),
            );
          },
        ),
      ),
    );
  }

  // The floating top bar laid over the field: back, title + mode/difficulty,
  // and the foot-guide toggle. (The settings shade opens from the scroller's
  // own left-edge pull-tab, not from here.) A translucent gradient keeps it
  // legible against the scrolling arrows, and a difficulty-coloured hairline
  // seats it.
  Widget _buildHeader(BuildContext context, Color diffColor) {
    final difficultyLabel = widget.difficultyLevel != null
        ? "${_pretty(widget.difficultyKey)} ${widget.difficultyLevel}"
        : _pretty(widget.difficultyKey);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: diffColor.withValues(alpha: 0.9), width: 2),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.blueGrey),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      difficultyLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: diffColor,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip:
                    _showFootGuide ? "Hide foot guide" : "Show foot guide",
                onPressed: () =>
                    setState(() => _showFootGuide = !_showFootGuide),
                icon: Icon(
                  _showFootGuide
                      ? Icons.directions_walk
                      : Icons.directions_walk_outlined,
                  color: _showFootGuide ? diffColor : Colors.blueGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pretty(String difficultyKey) =>
    difficultyKey.isEmpty ? "" : difficultyKey[0].toUpperCase() + difficultyKey.substring(1);
