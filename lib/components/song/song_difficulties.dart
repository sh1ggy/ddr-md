/// Name: SongDifficulties
/// Description: Widgets that display song difficulties.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

class SongDifficulty extends StatelessWidget {
  const SongDifficulty({
    super.key,
    required this.difficulty,
    this.highlightIndex,
  });

  final Difficulty difficulty;
  // Index into availableTypes of the chart to pick out. The others stay
  // legible but recede, so the strip still reads as the song's spread.
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: buildDiffList(difficulty),
        ),
      ),
    ]);
  }

  // Standard TextSpan component to render
  TextSpan diffTextSpan(
      {required String text, required Color color, bool dimmed = false}) {
    return TextSpan(
        text: text,
        style: TextStyle(
            fontSize: dimmed ? 13 : 15,
            color: dimmed ? color.withValues(alpha: 0.4) : color,
            fontWeight: dimmed ? FontWeight.normal : FontWeight.bold));
  }

  // Build out a list of TextSpan widgets to render as part of the difficulty list
  List<TextSpan> buildDiffList(Difficulty difficulty) {
    List<TextSpan> widgets = []; // Widgets list for difficulty TextSpans
    // Position among the charted difficulties, matching availableTypes' index.
    int chartIndex = -1;
    // Loop through entries in difficulty object and add accordingly
    for (var diff in difficulty.toJson().entries) {
      if (diff.value == null) {
        continue;
      }
      chartIndex++;
      final bool dimmed =
          highlightIndex != null && chartIndex != highlightIndex;
      switch (diff.key) {
        case ("beginner"):
          widgets.add(diffTextSpan(
              text: "${difficulty.beginner} \t", color: Colors.cyan, dimmed: dimmed));
          break;
        case ("easy"):
          widgets.add(diffTextSpan(
              text: "${difficulty.easy} \t", color: Colors.orange, dimmed: dimmed));
          break;
        case ("medium"):
          widgets.add(
              diffTextSpan(text: "${difficulty.medium} \t", color: Colors.red, dimmed: dimmed));
          break;
        case ("hard"):
          widgets.add(
              diffTextSpan(text: "${difficulty.hard} \t", color: Colors.green, dimmed: dimmed));
          break;
        case ("challenge"):
          widgets.add(diffTextSpan(
              text: "${difficulty.challenge} \t", color: Colors.purple, dimmed: dimmed));
          break;
      }
    }
    return widgets;
  }
}
