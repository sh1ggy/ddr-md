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

  final Difficulty difficulty;

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
        style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.bold));
  }

  // Build out a list of TextSpan widgets to render as part of the difficulty list
  List<TextSpan> buildDiffList(Difficulty difficulty) {
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

class SongNotecounts extends StatelessWidget {
  const SongNotecounts({
    super.key,
    required this.notecounts,
  });

  // Per-difficulty step counts, colour-matched to the levels row above
  final Difficulty notecounts;

  @override
  Widget build(BuildContext context) {
    if (notecounts.toJson().values.every((count) => count == null)) {
      return const SizedBox.shrink();
    }
    return Row(children: [
      const Icon(Icons.music_note, size: 14, color: Colors.grey),
      RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: buildCountList(notecounts),
        ),
      ),
    ]);
  }

  // Standard TextSpan component to render
  TextSpan countTextSpan({required String text, required Color color}) {
    return TextSpan(
        text: text,
        style:
            TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500));
  }

  // Build out a list of TextSpan widgets to render as part of the notecount list
  List<TextSpan> buildCountList(Difficulty notecounts) {
    List<TextSpan> widgets = []; // Widgets list for notecount TextSpans
    // Loop through entries in notecounts object and add accordingly
    for (var count in notecounts.toJson().entries) {
      if (count.value == null) {
        continue;
      }
      switch (count.key) {
        case ("beginner"):
          widgets.add(countTextSpan(
              text: "${notecounts.beginner} \t", color: Colors.cyan));
          break;
        case ("easy"):
          widgets.add(countTextSpan(
              text: "${notecounts.easy} \t", color: Colors.orange));
          break;
        case ("medium"):
          widgets.add(countTextSpan(
              text: "${notecounts.medium} \t", color: Colors.red));
          break;
        case ("hard"):
          widgets.add(countTextSpan(
              text: "${notecounts.hard} \t", color: Colors.green));
          break;
        case ("challenge"):
          widgets.add(countTextSpan(
              text: "${notecounts.challenge} \t", color: Colors.purple));
          break;
      }
    }
    return widgets;
  }
}
