/// Name: ChartAchievements
/// Parent: ChartBests, ScoreCard, JacketEdition
/// Description: Conservative per-play judgement and precision evidence.
library;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/db_models.dart';

/// Tap-only inference for existing combo artwork. This does not prove a
/// completed play: holds and shocks are absent from these five counts.
FullComboTier? judgedTapTier(
    int? marvelous, int? perfect, int? great, int? good, int? miss) {
  final counts = [marvelous, perfect, great, good, miss];
  if (counts.any((n) => n == null || n < 0) ||
      counts.fold(0, (sum, n) => sum + (n ?? 0)) == 0) {
    return null;
  }
  return fullComboTier(
      marvelous: marvelous!,
      perfect: perfect!,
      great: great!,
      good: good!,
      miss: miss!);
}

enum PrecisionAward { unknown, pfc, sdp, mfc }

typedef PrecisionEvidence = ({
  PrecisionAward award,
  String sourceRowId,
  int? perfects,
});

/// Every datum must come from this same play. A high money score or an
/// independently aggregated PFC lamp cannot supply missing completion proof.
PrecisionEvidence? precisionForPlay(Score play) {
  final taps = judgedTapTier(
      play.marvelous, play.perfect, play.great, play.good, play.miss);
  if (taps != FullComboTier.pfc && taps != FullComboTier.mfc) return null;
  final lamp = play.completionLamp;
  final PrecisionAward award;
  if (lamp == ClearLamp.mfc && taps == FullComboTier.mfc) {
    award = PrecisionAward.mfc;
  } else if (lamp == ClearLamp.pfc) {
    award = play.perfect! >= 1 && play.perfect! <= 9
        ? PrecisionAward.sdp
        : PrecisionAward.pfc;
  } else {
    return null;
  }
  return (award: award, sourceRowId: play.id, perfects: play.perfect);
}

PrecisionEvidence? bestPrecision(Iterable<Score> plays) {
  PrecisionEvidence? best;
  for (final play in plays) {
    final evidence = precisionForPlay(play);
    if (evidence != null &&
        (best == null ||
            evidence.award.index > best.award.index ||
            (evidence.award == best.award &&
                evidence.sourceRowId.compareTo(best.sourceRowId) < 0))) {
      best = evidence;
    }
  }
  return best;
}
