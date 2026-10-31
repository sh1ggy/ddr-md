/// Name: CardGains
/// Parent: EamuseSyncState, SessionWrapPage
/// Description: What a sync did to the player's cards: a chart's first best
/// collects its card, and a best that earns a card layer (AAA's foil, a
/// better lamp's frame, a higher flare's aura) upgrades it. Kept per chart
/// and layer, so a gain is only ever had once.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';

/// [card] is the card itself, new; the rest are the layers it can gain.
enum CardLayer { card, finish, frame, aura }

/// The frame a lamp puts round a card, from none (0) to MFC's (4): FC's
/// bronze, GFC's silver, PFC's gold, MFC's rainbow.
int cardFrameTier(ClearLamp? lamp) => switch (lamp) {
      ClearLamp.mfc => 4,
      ClearLamp.pfc => 3,
      ClearLamp.gfc => 2,
      ClearLamp.fc || ClearLamp.life4 => 1,
      _ => 0,
    };

/// Each of [old] and [add]'s score, grade, lamp and flare, whichever is
/// better, as the cabinet keeps them.
ChartBest mergeBest(ChartBest? old, ChartBest add) {
  final (score, grade, lamp, flare) =
      (old?.score, old?.grade, old?.lamp, old?.flare);
  return (
    score: score == null || (add.score != null && add.score! > score)
        ? add.score ?? score
        : score,
    // Grades run best first; lamps and flare ranks worst first.
    grade:
        grade == null || (add.grade != null && add.grade!.index < grade.index)
            ? add.grade ?? grade
            : grade,
    lamp: lamp == null || (add.lamp != null && add.lamp!.index > lamp.index)
        ? add.lamp ?? lamp
        : lamp,
    flare: flare == null ||
            (add.flare != null &&
                kFlareRanks.indexOf(add.flare!) > kFlareRanks.indexOf(flare))
        ? add.flare ?? flare
        : flare,
  );
}

class CardGain {
  CardGain({
    required this.song,
    required this.mode,
    required this.difficulty,
    required this.layer,
    this.from = '',
    this.to = '',
    this.fromScore,
    required this.best,
    required this.playedAt,
    required this.syncedAt,
  });

  final String song;
  final Modes mode;
  // Upper-case, as on [Score].
  final String difficulty;
  final CardLayer layer;
  // What the layer showed before and shows now: a grade's label, a lamp's
  // name or a flare rank; '' for none and for a new card.
  final String from, to;
  // The chart's best score before; null for a new card and gains recorded
  // before it was kept.
  final int? fromScore;
  // The chart's best once gained.
  final ChartBest best;
  final DateTime playedAt, syncedAt;

  /// The same on every device, and once per chart, layer and step.
  String get id => '$song:${mode.name}:$difficulty:${layer.name}:$to';

  ({String song, Modes mode, String difficulty}) get chart =>
      (song: song, mode: mode, difficulty: difficulty);

  Map<String, Object?> toMap() => {
        'id': id,
        'song': song,
        'mode': mode.name,
        'difficulty': difficulty,
        'layer': layer.name,
        'fromValue': from,
        'toValue': to,
        'fromScore': fromScore,
        'score': best.score,
        'grade': best.grade?.label,
        'lamp': best.lamp?.name,
        'flare': best.flare,
        'playedAt': playedAt.toUtc().toIso8601String(),
        'syncedAt': syncedAt.toUtc().toIso8601String(),
      };

  factory CardGain.fromMap(Map<String, dynamic> m) => CardGain(
        song: m['song'],
        mode: Modes.values.byName(m['mode']),
        difficulty: m['difficulty'],
        layer: CardLayer.values.byName(m['layer']),
        from: m['fromValue'],
        to: m['toValue'],
        fromScore: m['fromScore'] as int?,
        best: (
          score: m['score'] as int?,
          grade: Grade.values.where((g) => g.label == m['grade']).firstOrNull,
          lamp: ClearLamp.values.asNameMap()[m['lamp']],
          flare: m['flare'] as String?,
        ),
        playedAt: DateTime.parse(m['playedAt']),
        syncedAt: DateTime.parse(m['syncedAt']),
      );
}

/// The gains of a chart going from [before] to [after].
List<CardGain> cardGains(
    {required String song,
    required Modes mode,
    required String difficulty,
    required ChartBest? before,
    required ChartBest after,
    required DateTime playedAt,
    required DateTime syncedAt}) {
  CardGain gain(CardLayer layer, [String from = '', String to = '']) =>
      CardGain(
          song: song,
          mode: mode,
          difficulty: difficulty,
          layer: layer,
          from: from,
          to: to,
          fromScore: layer == CardLayer.card ? null : before?.score,
          best: after,
          playedAt: playedAt,
          syncedAt: syncedAt);
  if (before == null ||
      (before.score == null &&
          before.grade == null &&
          before.lamp == null &&
          before.flare == null)) {
    return [gain(CardLayer.card)];
  }
  return [
    if (after.grade == Grade.aaa && before.grade != Grade.aaa)
      gain(CardLayer.finish, before.grade?.label ?? '', Grade.aaa.label),
    if (cardFrameTier(after.lamp) > cardFrameTier(before.lamp))
      gain(CardLayer.frame, before.lamp?.name ?? '', after.lamp!.name),
    if (kFlareRanks.indexOf(after.flare ?? '') >
        kFlareRanks.indexOf(before.flare ?? ''))
      gain(CardLayer.aura, before.flare ?? '', after.flare!),
  ];
}
