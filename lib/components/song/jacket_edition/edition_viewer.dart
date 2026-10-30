/// Name: EditionViewer
/// Parent: SongDetails
/// Description: Refreshes a frozen chart's facts on score changes, off-frame.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'jacket_edition.dart';

// Shared route dimensions and transition for song jackets and lab previews.
Future<void> showEditionViewer(
  BuildContext context, {
  required EditionFacts facts,
  required EditionOptions options,
  required Widget artwork,
  Object? heroTag,
  bool refreshScores = true,
}) async {
  final still = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context).push<void>(PageRouteBuilder(
      transitionDuration: still ? Duration.zero : FloorPop.beat,
      reverseTransitionDuration: still ? Duration.zero : FloorPop.eighth,
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, __) {
        final card = refreshScores
            ? EditionViewer(facts: facts, options: options, child: artwork)
            : JacketEdition(facts: facts, options: options, child: artwork);
        return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: AspectRatio(
                            aspectRatio: 1,
                            child: heroTag == null
                                ? card
                                : Hero(
                                    tag: heroTag,
                                    transitionOnUserGestures: true,
                                    createRectTween: (begin, end) =>
                                        RectTween(begin: begin, end: end),
                                    flightShuttleBuilder:
                                        (_, __, ___, ____, _____) => artwork,
                                    child: card))))));
      }));
}

class EditionViewer extends StatefulWidget {
  const EditionViewer(
      {super.key,
      required this.facts,
      required this.options,
      required this.child});
  final EditionFacts facts;
  final EditionOptions options;
  final Widget child;
  @override
  State<EditionViewer> createState() => _EditionViewerState();
}

class _EditionViewerState extends State<EditionViewer> {
  late EditionFacts _facts = widget.facts;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    DatabaseProvider.achievementsRevision.addListener(_refresh);
  }

  @override
  void didUpdateWidget(EditionViewer old) {
    super.didUpdateWidget(old);
    _generation++;
    _facts = widget.facts;
  }

  Future<void> _refresh() async {
    if (!widget.options.effects) return;
    final generation = ++_generation;
    final facts = widget.facts;
    final mode = Modes.values.asNameMap()[facts.chart.mode];
    final difficulty = kInGameDifficultyNames[facts.chart.difficulty];
    if (mode == null || difficulty == null) return;
    try {
      await ChartBests.ensure(mode);
      if (!mounted || generation != _generation) return;
      final best = ChartBests.forChart(facts.chart.song, mode, difficulty);
      setState(() => _facts = EditionFacts(
          chart: facts.chart,
          level: facts.level,
          version: facts.version,
          grade: best?.grade,
          flare: best?.flare,
          lamp: best?.lamp,
          precision:
              ChartBests.precisionAt(facts.chart.song, mode, difficulty)));
    } catch (_) {
      // Existing material remains visible during a transient database error.
    }
  }

  @override
  void dispose() {
    DatabaseProvider.achievementsRevision.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JacketEdition(
      facts: _facts, options: widget.options, child: widget.child);
}
