/// Name: SongDifficulties
/// Description: Widgets that display song difficulties.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

class SongDifficulty extends StatelessWidget {
  const SongDifficulty({
    super.key,
    required this.difficulty,
  });

  final Double difficulty;

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
  TextSpan diffTextSpan({required String text, required Color color}) {
    return TextSpan(
        text: text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold));
  }

  // Build out a list of TextSpan widgets to render as part of the difficulty list
  List<TextSpan> buildDiffList(Double difficulty) {
    List<TextSpan> widgets = []; // Widgets list for difficulty TextSpans
    // Loop through entries in difficulty object and add accordingly
    for (var diff in difficulty.toJson().entries) {
      if (diff.value == null) {
        continue;
      }
      switch (diff.key) {
        case ("beginner"):
          widgets.add(diffTextSpan(
              text: "${difficulty.beginner} \t", color: Colors.cyan));
          break;
        case ("easy"):
          widgets.add(diffTextSpan(
              text: "${difficulty.easy} \t", color: Colors.orange));
          break;
        case ("medium"):
          widgets.add(
              diffTextSpan(text: "${difficulty.medium} \t", color: Colors.red));
          break;
        case ("hard"):
          widgets.add(
              diffTextSpan(text: "${difficulty.hard} \t", color: Colors.green));
          break;
        case ("challenge"):
          widgets.add(diffTextSpan(
              text: "${difficulty.challenge} \t", color: Colors.purple));
          break;
      }
    }
    return widgets;
  }
}
