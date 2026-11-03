/// Name: ScoringTierLabel
/// Parent: SongDetails, SongListItem, ArcadeGridTile
/// Description: A precise calculated scoring tier in cabinet lettering.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:flutter/material.dart';

class ScoringTierLabel extends StatelessWidget {
  const ScoringTierLabel(
      {super.key,
      required this.song,
      required this.mode,
      required this.index,
      this.compact = false,
      this.showMissing = false});
  final SongInfo song;
  final Modes mode;
  final int index;
  final bool compact;
  final bool showMissing;

  @override
  Widget build(BuildContext context) {
    final tier = song.scoringTierFor(mode, index);
    if (tier == null) {
      return showMissing
          ? const Text('Calculated: unavailable',
              style: TextStyle(fontSize: 11))
          : const SizedBox.shrink();
    }
    final types =
        (mode == Modes.singles ? song.singles : song.doubles).availableTypes;
    final difficulty =
        kInGameDifficultyNames[types[index.clamp(0, types.length - 1)]]!;
    return Tooltip(
      message:
          'Estimates scoring difficulty within the official level folder. Calculated from the chart.',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Calculated ', style: TextStyle(fontSize: compact ? 9 : 12)),
        LevelNumber(
            level: tier.tier.floor(),
            difficulty: difficulty,
            decimalHundredths: (tier.tier * 100).round() % 100,
            height: compact ? 11 : kLevelHeight),
      ]),
    );
  }
}
