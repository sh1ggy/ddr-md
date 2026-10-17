/// Name: DifficultyLabel
/// Parent: ScoreCard, ScoreRecordRow, SongPage, SongDifficultyPicker
/// Description: A chart's difficulty name and level drawn with the cabinet's
/// own lettering, from the optional git-ignored assets/difficulty/ art
/// (name_<difficulty>.png, level_<n>.png). Each piece falls back to plain
/// text when its art isn't bundled.
library;

import 'package:ddr_md/helpers.dart' show kInGameDifficultyColors;
import 'package:flutter/material.dart';

class DifficultyLabel extends StatelessWidget {
  const DifficultyLabel({
    super.key,
    required this.difficulty,
    this.level,
    this.height = 14,
  });

  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final int? level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = kInGameDifficultyColors[difficulty];
    Widget text(String s) => Text(s,
        style: TextStyle(
            fontSize: height,
            height: 1,
            fontWeight: FontWeight.bold,
            color: color));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The name art is dark lettering made to sit on a coloured band, so
        // it's tinted with the difficulty colour instead.
        Image.asset(
          'assets/difficulty/name_${difficulty.toLowerCase()}.png',
          height: height,
          color: color,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, __, ___) => text(difficulty),
        ),
        if (level != null) ...[
          SizedBox(width: height * 0.3),
          LevelNumber(level: level!, height: height * 1.3),
        ],
      ],
    );
  }
}

/// A chart level in the cabinet's numerals, white unless [color] tints it.
class LevelNumber extends StatelessWidget {
  const LevelNumber(
      {super.key, required this.level, this.height = 18, this.color});

  final int level;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/difficulty/level_$level.png',
        height: height,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
        errorBuilder: (_, __, ___) => Text('$level',
            style: TextStyle(
                fontSize: height * 0.75,
                height: 1,
                fontWeight: FontWeight.bold,
                color: color)),
      );
}
