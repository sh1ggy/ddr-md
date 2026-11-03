/// Name: ScoringTierLabel
/// Parent: SongDetails, SongListItem, ArcadeGridTile
/// Description: A precise chart tier using the shared Floor Pop readout.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class ScoringTierLabel extends StatelessWidget {
  const ScoringTierLabel(
      {super.key,
      required this.song,
      required this.mode,
      required this.index,
      this.compact = false});
  final SongInfo song;
  final Modes mode;
  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tier = song.scoringTierFor(mode, index);
    if (tier == null) {
      return const SizedBox.shrink();
    }
    final types =
        (mode == Modes.singles ? song.singles : song.doubles).availableTypes;
    final difficulty =
        kInGameDifficultyNames[types[index.clamp(0, types.length - 1)]]!;
    final pop = FloorPop.of(context);
    final number = LevelNumber(
      level: tier.tier.floor(),
      difficulty: difficulty,
      decimalHundredths: (tier.tier * 100).round() % 100,
      height: compact ? 12 : 14,
    );
    return Tooltip(
      message: 'Scoring difficulty within the official level folder.',
      child: compact
          ? number
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: pop.riser, borderRadius: BorderRadius.circular(8)),
              child: number,
            ),
    );
  }
}
