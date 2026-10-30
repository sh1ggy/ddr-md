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
    this.levelSuffix,
    this.height = kLevelHeight,
  });

  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final int? level;
  // Optional optical tier appended to a jacket level, e.g. 17.8.
  final int? levelSuffix;
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
          LevelNumber(
              level: level!,
              difficulty: difficulty,
              height: height,
              suffix: levelSuffix),
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
    this.suffix,
  });

  final int level;
  final int? suffix;
  // Upper-case in-game name, e.g. EXPERT.
  final String difficulty;
  final double height;
  // Recedes beside a highlighted chart.
  final bool dimmed;

  @override
  // Dimmed through the image's own paint alpha rather than an Opacity
  // layer, which a list full of rows would pay for per numeral.
  Widget build(BuildContext context) {
    Widget numeral(int value, {double? atHeight}) {
      final numberHeight = atHeight ?? height;
      return Image.asset(
          'assets/difficulty/level_${difficulty.toLowerCase()}_$value.png',
          height: numberHeight,
          opacity: dimmed ? const AlwaysStoppedAnimation(0.35) : null,
          errorBuilder: (_, __, ___) => Opacity(
              opacity: dimmed ? .35 : 1,
              child: _CabinetText('$value',
                  difficulty: difficulty,
                  height: numberHeight,
                  fill: Colors.black,
                  outline: Colors.white)));
    }

    if (suffix == null) return numeral(level);
    final fractionalHeight = height * .62;
    return Semantics(
        label: '$level.$suffix',
        child: ExcludeSemantics(
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              numeral(level),
              Padding(
                  padding: EdgeInsets.only(bottom: height * .04),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _CabinetText('.',
                            difficulty: difficulty,
                            height: fractionalHeight,
                            fill: Colors.black,
                            outline: Colors.white),
                        numeral(suffix!, atHeight: fractionalHeight),
                      ])),
            ])));
  }
}

/// A song's levels for one mode, Beginner to Challenge, skipping charts it
/// doesn't have. [highlightIndex] (into availableTypes) picks one out.
class LevelRow extends StatelessWidget {
  const LevelRow(
      {super.key,
      required this.levels,
      this.highlightIndex,
      this.height = kLevelHeight,
      this.packed = false});

  final Difficulty levels;
  final int? highlightIndex;
  final double height;
  // Charted levels sit side by side with an even gap instead of in fixed
  // columns, for spaces too narrow for all five slots.
  final bool packed;

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
      if (packed) {
        if (level == null) continue;
        if (cells.isNotEmpty) cells.add(SizedBox(width: height * 0.25));
        cells.add(child);
        continue;
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

/// Greys a level's numerals, for a level that isn't one chart's.
const kGreyLevel = ColorFilter.matrix([
  0.33, 0.33, 0.33, 0, 0, //
  0.33, 0.33, 0.33, 0, 0,
  0.33, 0.33, 0.33, 0, 0,
  0, 0, 0, 1, 0,
]);

class _LevelPickerState extends State<LevelPicker> {
  bool? _low;

  static const _anim = Duration(milliseconds: 250);

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
              : ColorFiltered(colorFilter: kGreyLevel, child: number),
        ),
      );
    }

    // One row at full size; scrolls sideways when it runs off screen.
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (low.isNotEmpty && low.length < widget.levels.length)
              Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _low = !showLow),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedRotation(
                        turns: showLow ? 0.5 : 0,
                        duration: _anim,
                        child: Icon(Icons.chevron_right,
                            size: widget.height * 0.8),
                      ),
                      AnimatedSize(
                        duration: _anim,
                        curve: Curves.easeOut,
                        child: showLow
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: ShapeDecoration(
                                    shape: const StadiumBorder(),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest),
                                child: ColorFiltered(
                                  colorFilter: kGreyLevel,
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        LevelNumber(
                                            level: low.first,
                                            difficulty: 'EXPERT',
                                            height: widget.height * 0.8),
                                        _CabinetText('-',
                                            difficulty: 'EXPERT',
                                            height: widget.height * 0.8,
                                            fill: Colors.black,
                                            outline: Colors.white),
                                        LevelNumber(
                                            level: low.last,
                                            difficulty: 'EXPERT',
                                            height: widget.height * 0.8),
                                      ]),
                                ),
                              ),
                      ),
                    ]),
                  ),
                ),
                // The low levels slide out from behind the toggle.
                ClipRect(
                  child: AnimatedSize(
                    duration: _anim,
                    curve: Curves.easeOut,
                    alignment: Alignment.centerLeft,
                    child: showLow
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: low.map(level).toList())
                        : const SizedBox.shrink(),
                  ),
                ),
              ])
            else if (showLow)
              ...low.map(level),
            ...widget.levels.where((l) => l >= 10).map(level),
          ],
        ));
  }
}
