/// Name: SongDifficultyPicker
/// Description: Picker for difficulty.
library;

import 'package:ddr_md/components/song_json.dart';
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

  // Standard TextSpan component to render
  Text diffTextSpan({required String text, required Color color}) {
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.bold));
  }

  // Build out a list of TextSpan widgets to render as part of the difficulty list
  List<Text> buildDiffList(Difficulty difficulty) {
    List<Text> widgets = []; // Widgets list for difficulty TextSpans
    // Loop through entries in difficulty object and add accordingly
    for (var diff in difficulty.toJson().entries) {
      if (diff.value == null) {
        continue;
      }
      widgets.add(diffTextSpan(
          text: "${diff.value}", color: difficultyColor(diff.key)));
    }
    return widgets;
  }
}
