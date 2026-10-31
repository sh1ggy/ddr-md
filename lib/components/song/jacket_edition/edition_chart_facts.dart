/// Name: EditionChartFacts
/// Parent: SongDetails, EditionViewer
/// Description: Refreshes one chart from the revision-aware bests cache off-frame.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:flutter/widgets.dart';
import 'edition_model.dart';

class EditionChartFacts extends StatefulWidget {
  const EditionChartFacts(
      {super.key,
      required this.facts,
      required this.enabled,
      required this.builder});
  final EditionFacts facts;
  final bool enabled;
  final Widget Function(BuildContext, EditionFacts) builder;
  @override
  State<EditionChartFacts> createState() => _EditionChartFactsState();
}

class _EditionChartFactsState extends State<EditionChartFacts> {
  late EditionFacts _facts = widget.facts;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    // The facts it's given are current; only a later score changes them.
    DatabaseProvider.achievementsRevision.addListener(_refresh);
  }

  @override
  void didUpdateWidget(EditionChartFacts old) {
    super.didUpdateWidget(old);
    if (old.facts.chart == widget.facts.chart &&
        old.facts.level == widget.facts.level &&
        old.facts.version == widget.facts.version &&
        old.facts.grade == widget.facts.grade &&
        old.facts.lamp == widget.facts.lamp &&
        old.facts.flare == widget.facts.flare &&
        old.facts.precision == widget.facts.precision &&
        old.facts.hardestTop == widget.facts.hardestTop &&
        old.facts.score == widget.facts.score &&
        old.enabled == widget.enabled) {
      return;
    }
    _generation++;
    _facts = widget.facts;
    _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.enabled) return;
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
          precision: ChartBests.precisionAt(facts.chart.song, mode, difficulty),
          score: best?.score,
          hardestTop:
              ChartBests.hardestTop(facts.chart.song, mode, difficulty)));
    } catch (_) {
      // Keep the current material through a transient database error.
    }
  }

  @override
  void dispose() {
    DatabaseProvider.achievementsRevision.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _facts);
}
