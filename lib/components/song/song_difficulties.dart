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
          children: <InlineSpan>[
            TextSpan(
                text:
                    difficulty.beginner != null ? "${difficulty.easy} \t" : "",
                style: const TextStyle(
                    color: Colors.cyan, fontWeight: FontWeight.bold)),
            TextSpan(
                text: difficulty.easy != null ? "${difficulty.easy} \t" : "",
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold)),
            TextSpan(
                text:
                    difficulty.medium != null ? "${difficulty.medium} \t" : "",
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
            TextSpan(
                text: difficulty.hard != null ? "${difficulty.hard} \t" : "",
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
            TextSpan(
                text:
                    difficulty.expert != null ? "${difficulty.expert} \t" : "",
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
            TextSpan(
                text: difficulty.challenge != null
                    ? "${difficulty.challenge} \t"
                    : "",
                style: const TextStyle(
                    color: Colors.purple, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ]);
  }
}
