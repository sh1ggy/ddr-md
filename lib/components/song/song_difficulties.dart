/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
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

  TextSpan diffTextSpan({required String text, required Color color}) {
    return TextSpan(
        text: text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold));
  }

  List<TextSpan> buildDiffList(Double difficulty) {
    Map<String, dynamic> json = difficulty.toJson();
    List<TextSpan> widgets = [];
    if (difficulty.beginner != null) {
      widgets.add(
          diffTextSpan(text: "${difficulty.beginner} \t", color: Colors.cyan));
    }
    if (difficulty.easy != null) {
      widgets.add(
          diffTextSpan(text: "${difficulty.easy} \t", color: Colors.orange));
    }
    if (difficulty.medium != null) {
      widgets.add(
          diffTextSpan(text: "${difficulty.medium} \t", color: Colors.red));
    }
    if (difficulty.hard != null) {
      widgets.add(
          diffTextSpan(text: "${difficulty.hard} \t", color: Colors.green));
    }
    if (difficulty.challenge != null) {
      widgets.add(diffTextSpan(
          text: "${difficulty.challenge} \t", color: Colors.purple));
    }
    return widgets;
  }
}
