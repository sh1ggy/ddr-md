/// Name: DifficultyLabel
/// Parent: ScoreCard, ScoreRecordRow, SongPage, SongDifficultyPicker
/// Description: A chart's difficulty name and level drawn with the cabinet's
/// own lettering, from the optional git-ignored assets/difficulty/ art
/// (name_<difficulty>.png, level_<difficulty>_<n>.png). Without the art, the
/// same look is drawn as text: heavy italic with an outline and a shadow in
/// the difficulty's colour.
library;

import 'package:ddr_md/helpers.dart' show kInGameDifficultyColors;
import 'package:flutter/material.dart';

class DifficultyLabel extends StatelessWidget {
  const DifficultyLabel({
    super.key,
    required this.difficulty,
    this.level,
    this.height = 16,
  });

  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final int? level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final name = difficulty.toLowerCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/difficulty/name_$name.png',
          height: height,
          errorBuilder: (_, __, ___) => _CabinetText(
              name[0].toUpperCase() + name.substring(1),
              difficulty: difficulty,
              height: height,
              fill: Colors.white,
              outline: Colors.black),
        ),
        if (level != null) ...[
          SizedBox(width: height * 0.25),
          LevelNumber(level: level!, difficulty: difficulty, height: height),
        ],
      ],
    );
  }
}

/// A chart level in the cabinet's numerals: black, outlined in white, with a
/// shadow in its difficulty's colour.
class LevelNumber extends StatelessWidget {
  const LevelNumber({
    super.key,
    required this.level,
    required this.difficulty,
    this.height = 18,
  });

  final int level;
  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/difficulty/level_${difficulty.toLowerCase()}_$level.png',
        height: height,
        errorBuilder: (_, __, ___) => _CabinetText('$level',
            difficulty: difficulty,
            height: height,
            fill: Colors.black,
            outline: Colors.white),
      );
}

class _CabinetText extends StatelessWidget {
  const _CabinetText(
    this.text, {
    required this.difficulty,
    required this.height,
    required this.fill,
    required this.outline,
  });

  final String text;
  final String difficulty;
  final double height;
  final Color fill;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final size = height * 0.8;
    final style = TextStyle(
      fontSize: size,
      height: 1.1,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
    );
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.22
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    return Stack(children: [
      Transform.translate(
        offset: Offset(size * 0.1, size * 0.12),
        child: Text(text,
            style: style.copyWith(
                foreground: stroke(
                    kInGameDifficultyColors[difficulty] ?? Colors.grey))),
      ),
      Text(text, style: style.copyWith(foreground: stroke(outline))),
      Text(text, style: style.copyWith(color: fill)),
    ]);
  }
}
