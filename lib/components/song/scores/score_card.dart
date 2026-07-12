/// Name: ScoreCard
/// Parent: ScoresTab, SongPage
/// Description: Card to display a saved score's fields from the DB.
/// When [header] is given (e.g. "Latest Score" on the song page) it is
/// shown on top and the date moves to the bottom, matching the
/// latest-note card layout.
library;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    required this.score,
    this.header,
  });

  final Score score;
  final String? header;

  // The full-combo tier is only meaningful when OCR captured every judgment
  // count; a missing field could hide the miss that breaks the combo.
  FullComboTier? _fullComboTier() {
    if (score.marvelous == null ||
        score.perfect == null ||
        score.great == null ||
        score.good == null ||
        score.miss == null) {
      return null;
    }
    return fullComboTier(
      marvelous: score.marvelous!,
      perfect: score.perfect!,
      great: score.great!,
      good: score.good!,
      miss: score.miss!,
    );
  }

  // Money score with the grade computed from it: icon where art exists,
  // grade label otherwise, plus the full-combo lamp when one was earned.
  Widget _buildScoreRow() {
    final grade = gradeForScore(score.score!);
    final gradeArt = gradeIcon(grade);
    final fcArt = switch (_fullComboTier()) {
      null || FullComboTier.none => null,
      final tier => fullComboIcon(tier),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gradeArt != null)
          Image.asset(gradeArt, height: 22)
        else
          Text(
            grade.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        const SizedBox(width: 8),
        Text(
          formatScore(score.score!),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        if (fcArt != null) ...[
          const SizedBox(width: 8),
          Image.asset(fcArt, height: 16),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = formatDate(DateTime.parse(score.date));
    final flareArt = score.flare.isNotEmpty ? flareIcon(score.flare) : null;
    final details = <Widget>[
      if (score.difficulty.isNotEmpty)
        Text(score.difficulty, style: const TextStyle(fontSize: 14)),
      if (flareArt != null)
        Image.asset(flareArt, height: 18)
      else if (score.flare.isNotEmpty)
        Text('Flare ${score.flare}', style: const TextStyle(fontSize: 14)),
      if (score.username.isNotEmpty)
        Text(score.username, style: const TextStyle(fontSize: 14)),
    ];
    return Card(
      child: ListTile(
        title: Column(
          children: [
            Text(
              header ?? dateText,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary),
            ),
            if (score.score != null) _buildScoreRow(),
            if (details.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: details
                    .expand((w) => [
                          const Text(' • ', style: TextStyle(fontSize: 14)),
                          w,
                        ])
                    .skip(1)
                    .toList(),
              ),
            _ScoreJudgments(score: score),
            if (header != null)
              Text(
                dateText,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
          ].expand((x) => [const SizedBox(height: 8), x]).skip(1).toList(),
        ),
      ),
    );
  }
}

// Placeholder shown in place of [ScoreCard] when a song has no saved
// score yet. Mirrors the Card + ListTile + header structure so the
// song page layout stays consistent whether or not a score exists.
class NoScoreCard extends StatelessWidget {
  const NoScoreCard({super.key, this.header = "Latest Score"});

  final String header;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Column(
          children: [
            Text(
              header,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary),
            ),
            Text(
              "No score recorded",
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ].expand((x) => [const SizedBox(height: 8), x]).skip(1).toList(),
        ),
      ),
    );
  }
}

// Row of judgment counts (and max combo), skipping fields the OCR
// didn't capture.
class _ScoreJudgments extends StatelessWidget {
  const _ScoreJudgments({required this.score});

  final Score score;

  @override
  Widget build(BuildContext context) {
    final judgments = <(String, String, int?)>[
      ('MARV.', 'marvelous', score.marvelous),
      ('PERF.', 'perfect', score.perfect),
      ('GREAT', 'great', score.great),
      ('GOOD', 'good', score.good),
      ('MISS', 'miss', score.miss),
      ('COMBO', 'combo', score.maxCombo),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (var (label, colorKey, value) in judgments)
          if (value != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: judgmentColor(colorKey) ??
                            Theme.of(context).colorScheme.onSurfaceVariant)),
                Text('$value',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
      ],
    );
  }
}
