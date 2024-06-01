/// Name: SongDifficulties
/// Description: Widgets that display song difficulties.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongDifficultyPicker extends StatefulWidget {
  const SongDifficultyPicker({
    super.key,
    required this.difficulty,
  });

  final Difficulty difficulty;

  @override
  State<SongDifficultyPicker> createState() => _SongDifficultyPickerState();
}

class _SongDifficultyPickerState extends State<SongDifficultyPicker> {
  List<bool> selectedDifficulty = [];
  @override
  void initState() {
    selectedDifficulty = List<bool>.generate(
        widget.difficulty.toJson().length, (index) => false);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();

    return Row(children: [
      ToggleButtons(
          onPressed: (int index) {
            setState(() {
              for (int i = 0; i < selectedDifficulty.length; i++) {
                if (i == index) {
                  selectedDifficulty[i] = true;
                  songState.setChosenDifficulty(i);
                  continue;
                }
                selectedDifficulty[i] = false;
                continue;
              }
            });
          },
          constraints: const BoxConstraints(
            minHeight: 30.0,
            minWidth: 40.0,
          ),
          isSelected: selectedDifficulty,
          children: buildDiffList(widget.difficulty)),
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
      switch (diff.key) {
        case ("beginner"):
          widgets.add(
              diffTextSpan(text: "${difficulty.beginner}", color: Colors.cyan));
          break;
        case ("easy"):
          widgets.add(
              diffTextSpan(text: "${difficulty.easy}", color: Colors.orange));
          break;
        case ("medium"):
          widgets.add(
              diffTextSpan(text: "${difficulty.medium}", color: Colors.red));
          break;
        case ("hard"):
          widgets.add(
              diffTextSpan(text: "${difficulty.hard}", color: Colors.green));
          break;
        case ("challenge"):
          widgets.add(diffTextSpan(
              text: "${difficulty.challenge}", color: Colors.purple));
          break;
      }
    }
    return widgets;
  }
}
