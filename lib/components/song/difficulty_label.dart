/// Name: DifficultyLabel
/// Parent: ScoreCard, ScoreRecordRow, SongPage, SongDifficultyPicker
/// Description: A chart's difficulty name and level drawn with the cabinet's
/// own lettering, from the optional git-ignored assets/difficulty/ art
/// (name_<difficulty>.png, level_<difficulty>_<n>.png). Without the art, the
/// same look is drawn as text: heavy italic with an outline and a shadow in
/// the difficulty's colour.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:ddr_md/components/song_json.dart' show Difficulty;
import 'package:ddr_md/helpers.dart'
    show kInGameDifficultyColors, kInGameDifficultyNames;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The size difficulty names and levels are drawn at on the song page and
/// score cards, and the smaller one shared by the song list's rows and tiles.
const double kLevelHeight = 19;
const double kSongListLevelHeight = 14;

class DifficultyLabel extends StatelessWidget {
  const DifficultyLabel({
    super.key,
    required this.difficulty,
    this.level,
    this.height = kLevelHeight,
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
    this.height = kLevelHeight,
    this.dimmed = false,
  });

  final int level;
  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final double height;
  // Recedes beside a highlighted chart.
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Image.asset(
          'assets/difficulty/level_${difficulty.toLowerCase()}_$level.png',
          height: height,
          errorBuilder: (_, __, ___) => _CabinetText('$level',
              difficulty: difficulty,
              height: height,
              fill: Colors.black,
              outline: Colors.white),
        ),
      );
}

/// A song's levels for one mode, Beginner to Challenge, skipping charts it
/// doesn't have. [highlightIndex] (into availableTypes) picks one out.
class LevelRow extends StatelessWidget {
  const LevelRow(
      {super.key,
      required this.levels,
      this.highlightIndex,
      this.height = kLevelHeight});

  final Difficulty levels;
  final int? highlightIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final charted = [
      for (final e in levels.toJson().entries)
        if (e.value != null) (kInGameDifficultyNames[e.key]!, e.value as int)
    ];
    final gap = height * 0.3;
    Widget number(int i) => LevelNumber(
        level: charted[i].$2,
        difficulty: charted[i].$1,
        height: height,
        dimmed: highlightIndex != null && i != highlightIndex);
    final profiles = [
      for (final (name, level) in charted)
        LevelProfiles.of('level_${name.toLowerCase()}_$level')
    ];
    if (charted.isEmpty || profiles.contains(null)) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < charted.length; i++)
          Padding(padding: EdgeInsets.only(right: gap), child: number(i)),
      ]);
    }
    // Kerned on the numerals' outlines: each one sits [gap] from the closest
    // point of the one before, so the italic overhangs don't make one-digit
    // and two-digit levels look unevenly spaced.
    final k = height / profiles.first!.h;
    final xs = <double>[0];
    for (var i = 1; i < profiles.length; i++) {
      final a = profiles[i - 1]!, b = profiles[i]!;
      var tightest = a.w;
      for (var y = 0; y < math.min(a.h, b.h); y++) {
        tightest = math.min(tightest, a.r[y] + b.l[y]);
      }
      xs.add(xs.last + (a.w - tightest) * k + gap);
    }
    return SizedBox(
      width: xs.last + profiles.last!.w * k,
      height: height,
      child: Stack(children: [
        for (var i = 0; i < xs.length; i++)
          Positioned(left: xs[i], top: 0, bottom: 0, child: number(i)),
      ]),
    );
  }
}

/// Each level numeral's width and, per row, how far its outline sits in from
/// the left and right edges, from the art's profiles.json. Empty without the
/// art.
class LevelProfiles {
  static Map<String, ({int w, int h, List<int> l, List<int> r})> _all = {};

  static ({int w, int h, List<int> l, List<int> r})? of(String name) =>
      _all[name];

  static Future<void> load() async {
    try {
      final json = jsonDecode(
              await rootBundle.loadString('assets/difficulty/profiles.json'))
          as Map<String, dynamic>;
      _all = {
        for (final MapEntry(:key, :value) in json.entries)
          key: (
            w: value['w'] as int,
            h: value['h'] as int,
            l: (value['l'] as List).cast<int>(),
            r: (value['r'] as List).cast<int>(),
          )
      };
    } catch (_) {
      // No art bundled; LevelRow spaces the text fallback evenly instead.
    }
  }
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
