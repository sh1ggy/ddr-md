/// Name: TierWidgets
/// Parent: YourTiersPage, PlaceTierSheet, CircleTiersPage, TierLeanPage
/// Description: Pieces the tier pages share: the Singles charts of a level,
/// a chart's jacket with how far your rung sits from the calculated one,
/// the level picker, and the switch for which tier rows show.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart'
    show kInGameDifficultyColors, kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

/// A Singles chart of a level, with its calculated rung if it has one.
typedef LevelChart = ({
  SongInfo song,
  int index,
  String difficulty,
  int level,
  int? calc
});

extension LevelChartKey on LevelChart {
  TierChart get key => (song.name, difficulty);
  bool get played =>
      ChartBests.forChart(song.name, Modes.singles, difficulty) != null;
  TierPlacement? get placement => YourTiers.of(song.name, difficulty, level);
}

/// Every Singles chart at [level].
List<LevelChart> chartsAt(int level) => [
      for (final song in Songs.list)
        for (final (i, key) in song.singles.availableTypes.indexed)
          if (song.singles.toJson()[key] == level)
            (
              song: song,
              index: i,
              difficulty: kInGameDifficultyNames[key]!,
              level: level,
              calc: song.scoringTierFor(Modes.singles, i)?.hundredths,
            )
    ];

/// The chart [song] / [difficulty] as a [LevelChart], when it's still at
/// [level].
LevelChart? levelChart(String song, String difficulty, int level) {
  final info = Songs.list.where((s) => s.name == song).firstOrNull;
  if (info == null) return null;
  final types = info.singles.availableTypes;
  final i = types.indexWhere((t) => kInGameDifficultyNames[t] == difficulty);
  if (i < 0 || info.singles.toJson()[types[i]] != level) return null;
  return (
    song: info,
    index: i,
    difficulty: difficulty,
    level: level,
    calc: info.scoringTierFor(Modes.singles, i)?.hundredths,
  );
}

/// Harder than the calculated tier in Coral, easier in Pad Blue.
Color tierDeltaColor(int delta) =>
    delta > 0 ? FloorPop.coral : FloorPop.padBlue;

/// A chart's jacket, with a chip for how far [rung] sits from its
/// calculated tier when they differ.
class TierJacket extends StatelessWidget {
  const TierJacket(this.chart,
      {super.key, this.rung, this.size = 48, this.placed = false});

  final LevelChart chart;
  final int? rung;
  final double size;
  // Outlined in Volt: the player has put it on its rung.
  final bool placed;

  @override
  Widget build(BuildContext context) {
    final delta = rung == null || chart.calc == null ? 0 : rung! - chart.calc!;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 5),
            child: Stack(fit: StackFit.expand, children: [
              SongArtwork(songName: chart.song.name, title: chart.song.title),
              // The difficulty along the foot, as on the song list's rows.
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    height: 3,
                    width: double.infinity,
                    child: ColoredBox(
                        color: kInGameDifficultyColors[chart.difficulty] ??
                            Colors.grey)),
              ),
            ]),
          ),
        ),
        if (placed)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size / 5),
                    border: Border.all(
                        color: FloorPop.of(context).voltText, width: 2)),
              ),
            ),
          ),
        if (delta != 0)
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: tierDeltaColor(delta),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(TierLean.label(delta),
                  style: FloorPop.readout(10,
                      color: delta > 0 ? FloorPop.onVolt : Colors.white)),
            ),
          ),
      ]),
    );
  }
}

/// Which tier rows and numerals show: calculated, yours or the circle's.
class TierShownSwitch extends StatelessWidget {
  const TierShownSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return ValueListenableBuilder(
      valueListenable: YourTiers.revision,
      builder: (context, _, __) {
        final shown = YourTiers.shown;
        Widget option(TierShown s, String label, Widget icon) {
          final on = s == shown;
          return Semantics(
            selected: on,
            button: true,
            label: label,
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => YourTiers.setShown(s),
                child: AnimatedContainer(
                  duration: FloorPop.eighth,
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: on ? FloorPop.volt : Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                  child: IconTheme(
                      data: IconThemeData(
                          size: 18, color: on ? FloorPop.onVolt : pop.haze),
                      child: icon),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: pop.riser, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            option(TierShown.calc, 'Calculated tiers',
                const Icon(Icons.bar_chart_rounded)),
            option(TierShown.mine, 'Your tiers', const Icon(Icons.person)),
            option(TierShown.circle, "Your circle's tiers",
                const Icon(Icons.groups_rounded)),
          ]),
        );
      },
    );
  }
}
