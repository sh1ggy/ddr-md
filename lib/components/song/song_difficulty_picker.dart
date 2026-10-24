/// Name: SongDifficultyPicker
/// Description: Picker for difficulty: a leaning tile per chart around the
/// cabinet's level numeral.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SongDifficultyPicker extends StatelessWidget {
  const SongDifficultyPicker({
    super.key,
    required this.difficulty,
  });

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();

    // One tile per difficulty the current mode actually has (e.g. doubles
    // has no beginner), selection derived from state so mode/song switches
    // can't leave a stale or out-of-range highlight.
    final charts = [
      for (final diff in difficulty.toJson().entries)
        if (diff.value != null)
          (level: diff.value as int, name: kInGameDifficultyNames[diff.key]!),
    ];
    if (charts.isEmpty) return const SizedBox.shrink();
    final chosen = songState.chosenDifficulty.clamp(0, charts.length - 1);
    final pop = FloorPop.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        for (final (i, chart) in charts.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == chosen,
              label: '${chart.name} ${chart.level}',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  songState.setChosenDifficulty(i);
                },
                child: Lean(
                  child: AnimatedContainer(
                    duration: FloorPop.eighth,
                    curve: FloorPop.step,
                    height: 56,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: i == chosen
                          ? kInGameDifficultyColors[chart.name]!
                              .withValues(alpha: 0.28)
                          : pop.riser,
                      borderRadius: BorderRadius.circular(12),
                      border: i == chosen
                          ? Border.all(
                              color: kInGameDifficultyColors[chart.name]!,
                              width: 2.5)
                          : null,
                      boxShadow: [
                        if (i == chosen)
                          BoxShadow(
                              color: kInGameDifficultyColors[chart.name]!
                                  .withValues(alpha: 0.5),
                              blurRadius: 22),
                      ],
                    ),
                    child: Stack(children: [
                      Center(
                        child: Upright(
                          child: LevelNumber(
                              level: chart.level,
                              difficulty: chart.name,
                              height: 24),
                        ),
                      ),
                      if (i != chosen)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 4,
                          child: ColoredBox(
                              color: kInGameDifficultyColors[chart.name]!),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
