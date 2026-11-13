/// Name: TierLeanPage
/// Parent: YourTiersPage
/// Description: The kinds of chart you rate harder or easier than their
/// calculated tiers, from your placements, and the unplayed charts your lean
/// moves furthest. Worked out on the phone.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class TierLeanPage extends StatefulWidget {
  const TierLeanPage({super.key});

  @override
  State<TierLeanPage> createState() => _TierLeanPageState();
}

typedef _Nudge = ({LevelChart chart, int to});

class _TierLeanPageState extends State<TierLeanPage> {
  List<_Nudge>? _nudges;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ChartBests.ensure(Modes.singles);
    await TierLean.ensure();
    await Future.wait(Songs.list.map((s) => PatternsLoader.cached(s.name)));
    final nudges = <_Nudge>[];
    for (var level = 1; level <= 19; level++) {
      for (final c in chartsAt(level)) {
        if (c.calc == null || c.played) continue;
        final key = c.song.singles.availableTypes[c.index];
        final to = TierLean.forYou(c.song, key, level, c.calc!);
        if (to != null && to != c.calc) nudges.add((chart: c, to: to));
      }
    }
    nudges.sort((a, b) =>
        (b.to - b.chart.calc!).abs().compareTo((a.to - a.chart.calc!).abs()));
    if (mounted) setState(() => _nudges = nudges.take(6).toList());
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final lean = TierLean.strongest();
    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: pop.stage,
              border: Border.all(color: pop.line),
              borderRadius: BorderRadius.circular(20)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        );
    return Scaffold(
      backgroundColor: pop.ink,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
            child: Row(children: [
              BackButton(),
              Expanded(child: PageTitle('Your lean')),
            ]),
          ),
          Expanded(
            child: _nudges == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    children: [
                      card([
                        Row(children: [
                          Expanded(
                              child: Text('HARDER FOR YOU', style: pop.label)),
                          Text('${TierLean.placed}',
                              style: FloorPop.readout(12, color: pop.haze)),
                          const SizedBox(width: 4),
                          Icon(Icons.person, size: 13, color: pop.haze),
                        ]),
                        const SizedBox(height: 14),
                        if (lean.isEmpty)
                          LinearProgressIndicator(
                              value: TierLean.placed / TierLean.minPlaced,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                              color: pop.voltText,
                              backgroundColor: pop.riser)
                        else
                          for (final (k, v) in lean) _LeanBar(k, v),
                      ]),
                      if (_nudges!.isNotEmpty)
                        card([
                          Text('UNPLAYED · FOR YOU', style: pop.label),
                          const SizedBox(height: 12),
                          for (final n in _nudges!) _NudgeRow(n),
                        ]),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

class _LeanBar extends StatelessWidget {
  const _LeanBar(this.category, this.lean);

  final ChartCategory category;
  final double lean;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final shown = TierLean.shown(lean);
    final color = tierDeltaColor(shown);
    final share = (lean.abs() / 30).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(kCategoryIcons[category], size: 18, color: pop.haze),
        const SizedBox(width: 8),
        SizedBox(
            width: 92,
            child: Text(kCategoryLabels[category]!,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(
          child: SizedBox(
            height: 12,
            child: LayoutBuilder(builder: (context, box) {
              final half = box.maxWidth / 2;
              return Stack(children: [
                Positioned(
                    left: half,
                    top: -3,
                    bottom: -3,
                    width: 1,
                    child: ColoredBox(color: pop.haze.withValues(alpha: .5))),
                Positioned(
                  left: lean >= 0 ? half : half - share * half,
                  width: share * half,
                  top: 2,
                  height: 8,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4))),
                ),
              ]);
            }),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(shown == 0 ? '—' : TierLean.label(shown),
              textAlign: TextAlign.right,
              style:
                  FloorPop.readout(13, color: shown == 0 ? pop.haze : color)),
        ),
      ]),
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow(this.nudge);

  final _Nudge nudge;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final c = nudge.chart;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        TierJacket(c, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text(c.song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
        LevelNumber(
            level: c.level,
            difficulty: c.difficulty,
            decimalHundredths: c.calc,
            decimalKind: TierKind.calc,
            dimmed: true,
            height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: pop.haze),
        ),
        LevelNumber(
            level: c.level,
            difficulty: c.difficulty,
            decimalHundredths: nudge.to,
            decimalKind: TierKind.forYou,
            height: 16),
      ]),
    );
  }
}
