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
import 'package:ddr_md/models/settings_model.dart';
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
    required this.minBpm,
    required this.maxBpm,
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

  /// The chart's authored BPM extremes (`true_min`/`true_max` from [Chart]),
  /// with [chartBpm] as the core (dominant) tempo between them. This is the
  /// same (min, core, max) trio the cabinet hands its speed option, and
  /// [maxBpm] is the divisor REAL SPEED derives its multiplier from.
  final int minBpm;
  final int maxBpm;

  /// BPM segments and stops for this chart, in seconds (from [Chart]). Rendered
  /// as timing markers in the scroller so the preview reflects tempo shifts.
  final List<Bpm> bpms;
  final List<Stop> stops;

  @override
  State<ChartPreviewPage> createState() => _ChartPreviewPageState();
}

class _ChartPreviewPageState extends State<ChartPreviewPage> {
  bool _showFootGuide = false;

  // Assist tick: audible tick as each note row crosses the receptors during
  // playback (chart-derived, no song audio involved). Persisted across previews.
  bool _assistTick = Settings.getInt(Settings.assistTickOnKey) == 1;

  void _toggleAssistTick() {
    setState(() => _assistTick = !_assistTick);
    Settings.setInt(Settings.assistTickOnKey, _assistTick ? 1 : 0);
  }

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
              minBpm: widget.minBpm,
              maxBpm: widget.maxBpm,
              bpms: widget.bpms,
              stops: widget.stops,
              showFootGuide: _showFootGuide,
              assistTickOn: _assistTick,
              onToggleFootGuide: () =>
                  setState(() => _showFootGuide = !_showFootGuide),
              onToggleAssistTick: _toggleAssistTick,
              headerBuilder: (context) => _buildHeader(context, diffColor),
            );
          },
        ),
      ),
    );
  }

  // The floating top bar laid over the field: back + title/mode/difficulty only.
  // The assist-tick and foot-guide toggles moved into the scroller's settings
  // shade (its own segment); the shade itself opens from the scroller's left-edge
  // pull-tab, so the header carries no action affordances at all. A translucent
  // gradient keeps it legible against the scrolling arrows, and a
  // difficulty-coloured hairline seats it.
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
              // Balances the leading back button so the title stays optically
              // centred now that the trailing action icons are gone.
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

String _pretty(String difficultyKey) =>
    difficultyKey.isEmpty ? "" : difficultyKey[0].toUpperCase() + difficultyKey.substring(1);
