/// Name: ScoreCard
/// Parent: ScoresTab, SongPage
/// Description: Card to display a saved score's fields from the DB.
/// When [header] is given (e.g. "Latest Score" on the song page) it is
/// shown on top behind [kLatestScoreIcon] and the date moves to the bottom,
/// matching the latest-note card layout.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/scores/art_badge.dart';
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
  });

  final Score score;
  final String? header;
  // When given (the scores list), tapping the card opens it — the score
  // details page. The song page's latest-score card leaves this null and
  // keeps its own open-history tap handler.
  final VoidCallback? onTap;

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
                  score: score.score!,
                  lampArt: scoreLampArt(score),
                  flare: score.flare),
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

/// Full-combo lamp art for a play, from its judgements. Only meaningful when
/// every count was captured; a missing one could hide the miss that breaks
/// the combo.
String? scoreLampArt(Score score) => judgedLampArt(
    score.marvelous, score.perfect, score.great, score.good, score.miss);

/// [scoreLampArt] from the counts alone, for a play not yet saved.
String? judgedLampArt(
    int? marvelous, int? perfect, int? great, int? good, int? miss) {
  if (marvelous == null ||
      perfect == null ||
      great == null ||
      good == null ||
      miss == null) {
    return null;
  }
  return switch (fullComboTier(
    marvelous: marvelous,
    perfect: perfect,
    great: great,
    good: good,
    miss: miss,
  )) {
    FullComboTier.none => null,
    final tier => fullComboIcon(tier),
  };
}

/// Clear art for a play with no full-combo tier, only when the synced best
/// vouches for it: a clear lamp on the same score, since the OCR can't tell a
/// pass from a fail and a lower play may not be the one that cleared.
String? _syncedClear(Score score, ScoreRecord? best) {
  final lamp = best?.clearLamp;
  if (lamp == null || lamp.index < ClearLamp.clear.index) return null;
  return score.score != null && score.score == best!.score ? clearIcon : null;
}

/// The song page's one-line score: a trophy, then the latest play, then the
/// synced best on the selected chart (or whichever of the two exists).
class LatestScoreLine extends StatelessWidget {
  const LatestScoreLine({super.key, this.score, this.best});

  final Score? score;
  final ScoreRecord? best;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(kLatestScoreIcon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: score?.score == null && best == null
                ? Text('No score recorded',
                    style:
                        TextStyle(fontSize: 14, color: scheme.onSurfaceVariant))
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [
                      if (score?.score != null)
                        ScoreBadges(
                            score: score!.score!,
                            lampArt: scoreLampArt(score!) ??
                                _syncedClear(score!, best),
                            flare: score!.flare),
                      if (score?.score != null && best != null)
                        const SizedBox(width: 16),
                      if (best != null) ...[
                        Icon(Icons.cloud_done_outlined,
                            size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        ScoreBadges(
                          score: best!.score ?? 0,
                          lampArt: clearLampIcon(best!.clearLamp),
                          flare: best!.flareRank,
                          dense: score?.score != null,
                        ),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Clear lamp art, where the lamp has one: the full combos, then the generic
/// clear for any other pass. Only synced records carry a lamp, so a clear is
/// always one Konami reported; failed and unknown show nothing.
String? clearLampIcon(ClearLamp? lamp) => switch (lamp) {
      ClearLamp.mfc => fullComboIcon(FullComboTier.mfc),
      ClearLamp.pfc => fullComboIcon(FullComboTier.pfc),
      ClearLamp.gfc => fullComboIcon(FullComboTier.gfc),
      ClearLamp.fc => fullComboIcon(FullComboTier.fc),
      ClearLamp.life4 || ClearLamp.clear || ClearLamp.assisted => clearIcon,
      _ => null,
    };

class _FlareBadge extends StatelessWidget {
  const _FlareBadge(this.flare, {this.ink = 14, this.height = 24});

  final String flare;
  final double ink;
  final double height;

  @override
  Widget build(BuildContext context) {
    final art = flare.isEmpty ? null : flareIcon(flare);
    return flare.isNotEmpty && art == null
        ? Text('Flare $flare', style: const TextStyle(fontSize: 14))
        : ArtBadge(art, aspect: kFlareAspect, ink: ink, height: height);
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
    final unit = dense ? 0.8 : 1.0;
    final ink = 14 * unit, height = 24 * unit;
    // Badges hold their width when empty, so score, grade, lamp and flare
    // line up down a list.
    final gap = SizedBox(width: 6 * unit);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 108 * unit,
          child: Text(formatScore(score),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 20 * unit,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        SizedBox(width: 8 * unit),
        ArtBadge(gradeIcon(grade),
            aspect: kGradeAspect, ink: ink, height: height),
        gap,
        ArtBadge(lampArt, aspect: kLampAspect, ink: ink, height: height),
        gap,
        _FlareBadge(flare, ink: ink, height: height),
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
        // Name and level in their own columns, so levels line up whatever
        // the name's length.
        SizedBox(
          width: 86,
          child: Align(
            alignment: Alignment.centerLeft,
            child: DifficultyLabel(difficulty: record.difficulty),
          ),
        ),
        SizedBox(
          width: 32,
          child: level == null
              ? null
              : Center(
                  child: LevelNumber(
                      level: level!, difficulty: record.difficulty)),
        ),
        const SizedBox(width: 8),
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
