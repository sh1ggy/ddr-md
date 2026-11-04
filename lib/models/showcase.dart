/// Name: ShowcaseCard
/// Parent: CircleState
/// Description: A published best, kept as the facts that render its card.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';

class ShowcaseCard {
  const ShowcaseCard(
      {required this.id,
      required this.song,
      required this.mode,
      required this.difficulty,
      required this.best,
      this.playedAt});
  final String id, song, difficulty;
  final Modes mode;
  final ChartBest best;
  final DateTime? playedAt;
  Map<String, Object?> toJson() => {
        'id': id,
        'song': song,
        'mode': mode.name,
        'difficulty': difficulty,
        'score': best.score,
        'grade': best.grade?.label ?? '',
        'lamp': best.lamp?.name ?? '',
        'flare': best.flare ?? '',
        'playedAt': playedAt?.toUtc().toIso8601String(),
      };

  factory ShowcaseCard.fromJson(Map m) => ShowcaseCard(
      id: m['id'] as String,
      song: m['song'] as String,
      mode: Modes.values.byName(m['mode'] as String),
      difficulty: m['difficulty'] as String,
      best: (
        score: m['score'] as int?,
        grade: Grade.values.where((g) => g.label == m['grade']).firstOrNull,
        lamp: ClearLamp.values.where((l) => l.name == m['lamp']).firstOrNull,
        flare: (m['flare'] as String?)?.isEmpty == true
            ? null
            : m['flare'] as String?
      ),
      playedAt: DateTime.tryParse(m['playedAt'] as String? ?? ''));
}
