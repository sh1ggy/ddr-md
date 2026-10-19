/// Name: DifficultyLabel
/// Parent: ScoreCard, ScoreRecordRow, SongPage, SongDifficultyPicker,
/// ChartPreviewPage
/// Description: A chart's difficulty name and level drawn with the cabinet's
/// own lettering, from the optional git-ignored assets/difficulty/ art
/// (name_<difficulty>.png, level_<difficulty>_<n>.png). Without the art, the
/// same look is drawn as text: heavy italic with an outline and a shadow in
/// the difficulty's colour.
library;

import 'dart:convert';

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
    final entries = levels.toJson();
    // One fixed slot per difficulty, Beginner to Challenge, so a level sits
    // in the same column on every row; charts a song lacks leave their slot
    // empty.
    final slot = height * 1.7;
    var charted = 0;
    final cells = <Widget>[];
    for (final key in kInGameDifficultyNames.keys) {
      final level = entries[key] as int?;
      Widget child = const SizedBox.shrink();
      if (level != null) {
        final i = charted++;
        child = LevelNumber(
            level: level,
            difficulty: kInGameDifficultyNames[key]!,
            height: height,
            dimmed: highlightIndex != null && i != highlightIndex);
      }
      cells.add(SizedBox(
          width: slot,
          height: height,
          child: Align(alignment: Alignment.centerLeft, child: child)));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: cells);
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

/// Levels as tappable numerals, grey unless selected, with 1–9 folded behind
/// a toggle since they're rarely picked. Opens unfolded when one is selected.
class LevelPicker extends StatefulWidget {
  const LevelPicker({
    super.key,
    required this.levels,
    required this.isSelected,
    required this.onTap,
    this.height = 22,
  });

  final List<int> levels;
  final bool Function(int level) isSelected;
  final ValueChanged<int> onTap;
  final double height;

  @override
  State<LevelPicker> createState() => _LevelPickerState();
}

class _LevelPickerState extends State<LevelPicker> {
  bool? _low;

  static const _grey = ColorFilter.matrix([
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final low = widget.levels.where((l) => l < 10).toList();
    final showLow = _low ??
        low.any(widget.isSelected) || low.length == widget.levels.length;
    Widget level(int l) {
      final number =
          LevelNumber(level: l, difficulty: 'EXPERT', height: widget.height);
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onTap(l),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: widget.isSelected(l)
              ? number
              : ColorFiltered(colorFilter: _grey, child: number),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (low.isNotEmpty && low.length < widget.levels.length)
          TextButton.icon(
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => setState(() => _low = !showLow),
            icon: Icon(showLow ? Icons.chevron_left : Icons.chevron_right,
                size: 18),
            label: const Text('1–9'),
          ),
        if (showLow) ...low.map(level),
        ...widget.levels.where((l) => l >= 10).map(level),
      ],
    );
  }
}
