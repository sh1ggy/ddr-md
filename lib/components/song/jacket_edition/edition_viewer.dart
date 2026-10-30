/// Name: EditionViewer
/// Parent: SongDetails
/// Description: Refreshes a frozen chart's facts on score changes, off-frame.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'jacket_edition.dart';

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
