/// Name: ScoreCard
/// Parent: ScoresTab, SongPage
/// Description: Card to display a saved score's fields from the DB.
/// When [header] is given (e.g. "Latest Score" on the song page) it is
/// shown on top and the date moves to the bottom, matching the
/// latest-note card layout.
library;

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

  @override
  Widget build(BuildContext context) {
    final dateText = formatDate(DateTime.parse(score.date));
    final details = [
      if (score.difficulty.isNotEmpty) score.difficulty,
      if (score.flare.isNotEmpty) 'Flare ${score.flare}',
      if (score.username.isNotEmpty) score.username,
    ].join(' • ');
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
            if (score.score != null)
              Text(
                formatScore(score.score!),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            if (details.isNotEmpty)
              Text(details, style: const TextStyle(fontSize: 14)),
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
