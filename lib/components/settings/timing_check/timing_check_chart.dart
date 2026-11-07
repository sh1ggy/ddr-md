/// Name: TimingCheckChart
/// Parent: TimingCheckPage
/// Description: Renders the test chart through the chart preview's note field.
library;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song/notes/ddr_atlas.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'timing_check_protocol.dart';

class TimingCheckChart extends StatelessWidget {
  const TimingCheckChart({
    super.key,
    required this.playhead,
    required this.crossingMs,
    required this.constantMs,
    this.practice = false,
  });

  final ValueListenable<double> playhead;
  final int crossingMs;
  final int constantMs;
  final bool practice;

  static const _lanes = [0, 2, 1, 3, 2, 0, 3, 1, 3, 2, 0, 1, 2, 3, 1, 0];
  static final _timing = ChartTiming.build(
    [Bpm(st: 0, ed: roundEndMs / 1000, val: 60000 ~/ beatMs)],
    const [],
  );
  static final _notes = [
    for (var beat = -countInBeats; beat < scoredBeats; beat++)
      StepNote(
        beat: beat < 0 ? beat + countInBeats + 0.5 : beat.toDouble(),
        second: (firstBeatMs + beat * beatMs) / 1000,
        col: beat < 0 ? 1 : _lanes[beat],
        type: StepType.tap,
      ),
  ];

  // Keep the prior beat and the next loop's visible arrows at the seam.
  static final _practiceNotes = [
    for (var beat = -1; beat < 2 * scoredBeats; beat++)
      StepNote(
        beat: beat.toDouble(),
        second: beat * beatMs / 1000,
        col: _lanes[beat % scoredBeats],
        type: StepType.tap,
      ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final arrowSize = ChartPainter.arcadeArrowSize(
              constraints.biggest, kSingleDirs.length, 0);
          if (arrowSize == 0) return const SizedBox.expand();
          final travel = arrowSize * ChartPainter.cabinetTravelArrows;
          return ClipRect(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                willChange: true,
                painter: ChartPainter(
                  notes: practice ? _practiceNotes : _notes,
                  holds: const [],
                  shockNotes: const {},
                  shocks: const [],
                  bpmMarkers: const [],
                  stopMarkers: const [],
                  feet: const {},
                  footPrev: const {},
                  dirs: kSingleDirs,
                  colMap: const [0, 1, 2, 3],
                  playhead: playhead,
                  pxPerSecond: travel * 1000 / constantMs,
                  pxPerBeat: travel * beatMs / constantMs,
                  timing: _timing,
                  columnCount: kSingleDirs.length,
                  skin: SpriteNoteskin.resolvedSkin ?? const VectorNoteskin(),
                  ddr: DdrAtlas.resolvedAtlas,
                  arrowBlink: Settings.getInt(Settings.staticArrowsOnKey) == 0,
                  playing: true,
                  showHitEffects: false,
                  constantMs: constantMs.toDouble(),
                  visualOffset: -crossingMs / 1000,
                ),
              ),
            ),
          );
        },
      );
}
