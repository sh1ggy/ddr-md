/// Name: SongDifficultyPicker
/// Description: Picker for difficulty.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongDifficultyPicker extends StatelessWidget {
  const SongDifficultyPicker({
    super.key,
    required this.difficulty,
  });

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();

    // One button per difficulty the current mode actually has (e.g. doubles
    // has no beginner), selection derived from state so mode/song switches
    // can't leave a stale or out-of-range highlight.
    final buttons = buildDiffList(difficulty);
    if (buttons.isEmpty) return const SizedBox.shrink();
    final chosen = songState.chosenDifficulty.clamp(0, buttons.length - 1);

    return Row(children: [
      ToggleButtons(
          onPressed: (int index) => songState.setChosenDifficulty(index),
          constraints: const BoxConstraints(
            minHeight: 30.0,
            minWidth: 40.0,
          ),
          isSelected:
              List<bool>.generate(buttons.length, (index) => index == chosen),
          children: buttons),
    ]);
  }

  // One level per chart the mode has, in its difficulty's colour.
  List<Widget> buildDiffList(Difficulty difficulty) => [
        for (var diff in difficulty.toJson().entries)
          if (diff.value != null)
            LevelNumber(
                level: diff.value as int,
                height: 20,
                color: difficultyColor(diff.key)),
      ];
}
