/// Name: ScoreCard
/// Parent: ScoresTab, SongPage
/// Description: Card to display a saved score's fields from the DB.
/// When [header] is given (e.g. "Latest Score" on the song page) it is
/// shown on top behind [kLatestScoreIcon] and the date moves to the bottom,
/// matching the latest-note card layout.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart' show Modes;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const kLatestScoreIcon = Icons.emoji_events_outlined;

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    required this.score,
    this.header,
    this.onTap,
    this.best,
  });

  final Score score;
  // The synced best on the chart the song page has selected, shown under the
  // latest play.
  final ScoreRecord? best;
  final String? header;
  // When given (the scores list), tapping the card opens it — the score
  // details page. The song page's latest-score card leaves this null and
  // keeps its own open-history tap handler.
  final VoidCallback? onTap;

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

  String? get _lampArt => switch (_fullComboTier()) {
        null || FullComboTier.none => null,
        final tier => fullComboIcon(tier),
      };

  // The chart level for this score's difficulty, resolved from the song the
  // page is showing. Null when the difficulty doesn't name one of the song's
  // charts (raw OCR text) or the card is somehow shown for another song.
  int? _chartLevel(BuildContext context) {
    final song = Provider.of<SongState>(context, listen: false).songInfo;
    if (song == null ||
        (song.titletranslit != score.songTitle &&
            song.title != score.songTitle)) {
      return null;
    }
    final levels = score.mode == Modes.singles ? song.singles : song.doubles;
    for (final (name, level) in difficultyOptions(levels)) {
      if (name == score.difficulty) return level;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dateText = formatDate(DateTime.parse(score.playedAt));
    final flare = score.flare.isNotEmpty ? _FlareBadge(score.flare) : null;
    final level = _chartLevel(context);
    final details = <Widget>[
      if (score.difficulty.isNotEmpty)
        kInGameDifficultyColors.containsKey(score.difficulty)
            ? DifficultyLabel(difficulty: score.difficulty, level: level)
            : Text(score.difficulty,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      // The flare rank rides with the score row; it only lands here when
      // there is no score to attach it to.
      if (flare != null && score.score == null) flare,
    ];
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Column(
          children: [
            // Header/date line with a small badge marking how the score was
            // captured — live camera OCR vs an imported screenshot.
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (header != null) ...[
                  Icon(kLatestScoreIcon,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                _SourceBadge(source: score.source),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    header ?? dateText,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
            if (score.score != null)
              ScoreBadges(
                  score: score.score!, lampArt: _lampArt, flare: score.flare),
            if (best != null) _BestLine(best!),
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
  const NoScoreCard({super.key, this.header = "Latest Score", this.best});

  final String header;
  final ScoreRecord? best;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(kLatestScoreIcon,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  header,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            if (best != null)
              _BestLine(best!)
            else
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

// Small badge marking how a score was captured: live camera OCR vs an
// imported screenshot (load image). Icons mirror the two entry points on the
// OCR page (videocam / photo library).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final ScoreSource source;

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip) = switch (source) {
      ScoreSource.camera => (
          Icons.videocam_outlined,
          'Captured with camera OCR'
        ),
      ScoreSource.loadImage => (
          Icons.photo_library_outlined,
          'Imported from a screenshot'
        ),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      ('EX', 'exScore', score.exScore),
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
                        color: judgmentColor(colorKey, context: context) ??
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

/// Clear lamp art, where the lamp has one: the full combos and LIFE4.
String? clearLampIcon(ClearLamp? lamp) => switch (lamp) {
      ClearLamp.mfc => fullComboIcon(FullComboTier.mfc),
      ClearLamp.pfc => fullComboIcon(FullComboTier.pfc),
      ClearLamp.gfc => fullComboIcon(FullComboTier.gfc),
      ClearLamp.fc => fullComboIcon(FullComboTier.fc),
      ClearLamp.life4 => 'assets/icons/cl_li4clear.png',
      _ => null,
    };

class _FlareBadge extends StatelessWidget {
  const _FlareBadge(this.flare, {this.height = 18});

  final String flare;
  final double height;

  @override
  Widget build(BuildContext context) {
    final art = flareIcon(flare);
    return art != null
        ? Image.asset(art, height: height)
        : Text('Flare $flare', style: const TextStyle(fontSize: 14));
  }
}

/// Grade, money score, clear lamp and flare badge on one line.
class ScoreBadges extends StatelessWidget {
  const ScoreBadges({
    super.key,
    required this.score,
    this.lampArt,
    this.flare = '',
    this.dense = false,
  });

  final int score;
  final String? lampArt;
  final String flare;
  // Smaller, for list rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final grade = gradeForScore(score);
    final gradeArt = gradeIcon(grade);
    final unit = dense ? 0.8 : 1.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gradeArt != null)
          Image.asset(gradeArt, height: 22 * unit)
        else
          Text(grade.label,
              style:
                  TextStyle(fontSize: 16 * unit, fontWeight: FontWeight.bold)),
        SizedBox(width: 8 * unit),
        Text(formatScore(score),
            style: TextStyle(fontSize: 20 * unit, fontWeight: FontWeight.w600)),
        if (lampArt != null) ...[
          SizedBox(width: 8 * unit),
          Image.asset(lampArt!, height: 16 * unit),
        ],
        if (flare.isNotEmpty) ...[
          SizedBox(width: 8 * unit),
          _FlareBadge(flare, height: 18 * unit),
        ],
      ],
    );
  }
}

/// One chart's best: difficulty and level, then its badges.
class ScoreRecordRow extends StatelessWidget {
  const ScoreRecordRow({super.key, required this.record, this.level});

  final ScoreRecord record;
  final int? level;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 108,
          child: Align(
            alignment: Alignment.centerLeft,
            child: DifficultyLabel(
                difficulty: record.difficulty, level: level, height: 13),
          ),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ScoreBadges(
              score: record.score ?? 0,
              lampArt: clearLampIcon(record.clearLamp),
              flare: record.flareRank,
              dense: true,
            ),
          ),
        ),
        Icon(
            record.source == ScoreRecordSource.eamuse
                ? Icons.cloud_done_outlined
                : Icons.edit_outlined,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ]),
    );
  }
}

class _BestLine extends StatelessWidget {
  const _BestLine(this.best);

  final ScoreRecord best;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('BEST ',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ScoreBadges(
        score: best.score ?? 0,
        lampArt: clearLampIcon(best.clearLamp),
        flare: best.flareRank,
        dense: true,
      ),
    ]);
  }
}
