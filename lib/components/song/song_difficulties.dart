/// Name: SongDifficulties
/// Description: A song's levels on the song list.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:flutter/material.dart';

class SongDifficulty extends StatelessWidget {
  const SongDifficulty({
    super.key,
    required this.difficulty,
    this.highlightIndex,
    this.highlightTier,
    this.highlightKind = TierKind.calc,
  });

  final Difficulty difficulty;
  // Index into availableTypes of the chart to pick out. The others stay
  // legible but recede, so the strip still reads as the song's spread.
  final int? highlightIndex;
  // The highlighted chart's scoring tier hundredths.
  final int? highlightTier;
  final TierKind highlightKind;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: LevelRow(
            levels: difficulty,
            highlightIndex: highlightIndex,
            highlightTier: highlightTier,
            highlightKind: highlightKind,
            height: kSongListLevelHeight),
      );
}
