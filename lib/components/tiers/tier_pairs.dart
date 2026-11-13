/// Name: TierPairs
/// Parent: SessionWrapPage
/// Description: The session wrap's "harder to score?": up to three pairs of
/// Singles charts played that night at the same level, closest in tier
/// first. Picking one puts both on your tier list with the harder one above;
/// "about the same" puts them on one rung.
library;

import 'package:ddr_md/components/session/recent_plays.dart' show playChart;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/db_models.dart' show RecentPlay;
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

typedef TierPair = (LevelChart, LevelChart);

int _rungOf(LevelChart c) => c.placement?.hundredths ?? c.calc!;

/// The pairs to ask about from [plays]: charts with a calculated tier, two
/// at a time at one level, those whose rungs sit closest first.
List<TierPair> tierPairs(List<RecentPlay> plays, {int count = 3}) {
  final byLevel = <int, Map<TierChart, LevelChart>>{};
  for (final p in plays) {
    if (p.mode != Modes.singles || p.song == null) continue;
    final level = playChart(p).level;
    if (level == null) continue;
    final c = levelChart(p.song!, p.difficulty, level);
    if (c == null || c.calc == null) continue;
    byLevel.putIfAbsent(level, () => {})[c.key] = c;
  }
  final pairs = <TierPair>[];
  for (final charts in byLevel.values) {
    final sorted = charts.values.toList()
      ..sort((a, b) => _rungOf(a).compareTo(_rungOf(b)));
    for (var i = 0; i + 1 < sorted.length; i += 2) {
      pairs.add((sorted[i], sorted[i + 1]));
    }
  }
  pairs.sort((a, b) => (_rungOf(a.$1) - _rungOf(a.$2))
      .abs()
      .compareTo((_rungOf(b.$1) - _rungOf(b.$2)).abs()));
  return pairs.take(count).toList();
}

class TierPairs extends StatefulWidget {
  const TierPairs(this.pairs, {super.key});

  final List<TierPair> pairs;

  @override
  State<TierPairs> createState() => _TierPairsState();
}

class _TierPairsState extends State<TierPairs> {
  int _at = 0;
  // The last answer's move, shown under the next pair.
  ({LevelChart chart, int from, int to})? _moved;
  final _levels = <int, int>{};
  late final CircleState _circle = context.read<CircleState>();

  @override
  void dispose() {
    final busiest = _levels.entries.fold<MapEntry<int, int>?>(
        null, (b, e) => b == null || e.value > b.value ? e : b);
    if (busiest != null) {
      _circle.shareTiers(post: (level: busiest.key, count: busiest.value));
    }
    super.dispose();
  }

  /// [harder] null: about the same.
  Future<void> _answer(LevelChart? harder) async {
    HapticFeedback.selectionClick();
    final (a, b) = widget.pairs[_at];
    final level = a.level, step = tierStep(level), top = 100 - step;
    var ra = _rungOf(a), rb = _rungOf(b);
    final before = (a: ra, b: rb);
    if (harder == null) {
      ra = rb = onRung(level, (ra + rb) ~/ 2);
    } else {
      final up = harder == a;
      var hi = up ? ra : rb, lo = up ? rb : ra;
      if (hi <= lo) hi = lo + step;
      if (hi > top) {
        hi = top;
        lo = top - step;
      }
      (ra, rb) = up ? (hi, lo) : (lo, hi);
    }
    await YourTiers.place(a.song.name, a.difficulty, level, ra);
    await YourTiers.place(b.song.name, b.difficulty, level, rb);
    _levels[level] = (_levels[level] ?? 0) + 2;
    final movedA = (ra - before.a).abs() >= (rb - before.b).abs();
    setState(() {
      _moved = movedA
          ? (chart: a, from: before.a, to: ra)
          : (chart: b, from: before.b, to: rb);
      _at++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final done = _at >= widget.pairs.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Transform(
              transform: FloorPop.titleLean,
              child: Text('Harder to score?', style: FloorPop.display(20)),
            ),
          ),
          for (var i = 0; i < widget.pairs.length; i++)
            Container(
              width: 18,
              height: 5,
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                  color: i <= _at ? pop.voltText : pop.line,
                  borderRadius: BorderRadius.circular(3)),
            ),
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: done
              ? Center(
                  child: Icon(Icons.check_circle_rounded,
                      size: 56, color: pop.voltText, semanticLabel: 'Done'))
              : Row(spacing: 12, children: [
                  for (final c in [widget.pairs[_at].$1, widget.pairs[_at].$2])
                    Expanded(child: _Pick(c, onTap: () => _answer(c))),
                ]),
        ),
        if (_moved case final m?) ...[
          const SizedBox(height: 14),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: pop.ink, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text(m.chart.song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Text(rungLabel(m.from),
                  style: FloorPop.readout(15, color: pop.haze)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 16, color: pop.voltText),
              ),
              Text(rungLabel(m.to),
                  style: FloorPop.readout(15, color: pop.voltText)),
            ]),
          ),
        ],
        if (!done) ...[
          const SizedBox(height: 14),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                GhostButton(
                    onPressed: () => _answer(null),
                    child: const Text('About the same')),
                GhostButton(
                    onPressed: () => setState(() => _at++),
                    child: const Text('Skip')),
              ]),
        ],
      ]),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick(this.chart, {required this.onTap});

  final LevelChart chart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final shown = chart.song.shownTierFor(Modes.singles, chart.index);
    return Material(
      color: pop.riser,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SongArtwork(
                        songName: chart.song.name, title: chart.song.title)),
              ),
              const SizedBox(height: 10),
              Text(chart.song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 8),
              DifficultyLabel(difficulty: chart.difficulty, height: 14),
              const SizedBox(height: 6),
              LevelNumber(
                  level: chart.level,
                  difficulty: chart.difficulty,
                  decimalHundredths: shown?.hundredths,
                  decimalKind: shown?.kind ?? TierKind.calc,
                  height: 22),
            ],
          ),
        ),
      ),
    );
  }
}
