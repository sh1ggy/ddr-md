/// Name: TierChips
/// Parent: SongDetails
/// Description: The chosen Singles chart's three tiers side by side: yours,
/// your circle's median and the calculated one. They double as the switch
/// for which tier rows show; yours also opens the sheet to place the chart,
/// once you've played it.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/tiers/place_tier_sheet.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TierChips extends StatefulWidget {
  const TierChips({super.key, required this.song});

  final SongInfo song;

  @override
  State<TierChips> createState() => _TierChipsState();
}

class _TierChipsState extends State<TierChips> {
  @override
  void initState() {
    super.initState();
    // Without bests, nothing reads as played and the chips still show.
    ChartBests.ensure(Modes.singles).then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final songState = context.watch<SongState>();
    if (songState.modes != Modes.singles) return const SizedBox.shrink();
    final at =
        widget.song.tierChartAt(Modes.singles, songState.chosenDifficulty);
    if (at == null) return const SizedBox.shrink();
    final chart = levelChart(widget.song.name, at.difficulty, at.level);
    if (chart == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: YourTiers.revision,
      builder: (context, _, __) {
        final shown = YourTiers.shown;
        final mine = chart.placement?.hundredths;
        final forYou = mine != null || chart.played || chart.calc == null
            ? null
            : TierLean.forYou(chart.song, at.key, at.level, chart.calc!);
        final median = YourTiers.circleMedian(
            chart.song.name, chart.difficulty, chart.level);
        if (chart.calc == null && mine == null && median == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Row(spacing: 10, children: [
            _Chip(
              label: 'Your tier',
              selected: shown == TierShown.mine,
              icon: Icons.person,
              level: chart.level,
              hundredths: mine ?? forYou ?? (chart.played ? chart.calc : null),
              outlined: mine == null && forYou != null,
              faded: mine == null && forYou == null,
              onTap: () async {
                await YourTiers.setShown(TierShown.mine);
                if (chart.played && context.mounted) {
                  await showPlaceTierSheet(context, chart);
                }
              },
            ),
            _Chip(
              label: "Your circle's tier",
              selected: shown == TierShown.circle,
              icon: Icons.groups_rounded,
              level: chart.level,
              hundredths: median,
              onTap: () => YourTiers.setShown(TierShown.circle),
            ),
            _Chip(
              label: 'Calculated tier',
              selected: shown == TierShown.calc,
              icon: Icons.bar_chart_rounded,
              level: chart.level,
              hundredths: chart.calc,
              onTap: () => YourTiers.setShown(TierShown.calc),
            ),
          ]),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label,
      required this.selected,
      required this.icon,
      required this.level,
      required this.hundredths,
      required this.onTap,
      this.outlined = false,
      this.faded = false});

  final String label;
  final bool selected;
  final IconData icon;
  final int level;
  final int? hundredths;
  final VoidCallback onTap;
  // A "for you" tier rather than one you placed.
  final bool outlined;
  // Played but not placed: the calculated tier it starts on.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final ink =
        selected ? FloorPop.onVolt : Theme.of(context).colorScheme.onSurface;
    final text = hundredths == null ? '—' : '$level${rungLabel(hundredths!)}';
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label $text',
        child: Material(
          color: selected ? FloorPop.volt : pop.riser,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 60,
              child: ExcludeSemantics(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: selected ? FloorPop.onVolt : pop.haze),
                      const SizedBox(height: 4),
                      Text(text,
                          style: outlined && hundredths != null
                              ? FloorPop.readout(19).copyWith(
                                  foreground: Paint()
                                    ..style = PaintingStyle.stroke
                                    ..strokeWidth = 1.2
                                    ..color = ink)
                              : FloorPop.readout(19,
                                  color: faded && hundredths != null
                                      ? ink.withValues(alpha: .45)
                                      : ink)),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
